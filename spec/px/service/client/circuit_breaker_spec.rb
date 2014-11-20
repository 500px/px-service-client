require 'spec_helper'

describe Px::Service::Client::CircuitBreaker do
  subject {
    Class.new.include(Px::Service::Client::CircuitBreaker).tap do |c|
      # Anonymous classes don't have a name.  Stub out :name so that things work
      allow(c).to receive(:name).and_return("CircuitBreaker")
    end
  }

  describe '#included' do
    it "excludes Px::Service::ServiceRequestError by default" do
      expect(subject.circuit_handler.excluded_exceptions).to include(Px::Service::ServiceRequestError)
    end

    it "sets the failure threshold" do
      expect(subject.circuit_handler.failure_threshold).to eq(5)
    end

    it "sets the failure timeout" do
      expect(subject.circuit_handler.failure_timeout).to eq(7)
    end

    it "sets the invocation timeout" do
      expect(subject.circuit_handler.invocation_timeout).to eq(5)
    end
  end

  describe '#circuit_method' do
    context "when the wrapped method succeeds" do
      before :each do
        subject.send(:define_method, :test_method) do |arg|
          "returned #{arg}"
        end

        subject.circuit_method(:test_method)
      end

      it "returns the return value" do
        expect(subject.instance.test_method("test")).to eq("returned test")
      end
    end

    context "when the wrapped method fails with a ServiceRequestError" do
      before :each do
        subject.send(:define_method, :test_method) do |arg|
          raise Px::Service::ServiceRequestError.new("Error", 404)
        end

        subject.circuit_method(:test_method)
      end

      it "raises a ServiceRequestError" do
        expect{
          subject.instance.test_method("test")
        }.to raise_error(Px::Service::ServiceRequestError, "Error")
      end
    end

    context "when the wrapped method fails with a ServiceError" do
      before :each do
        subject.send(:define_method, :test_method) do |arg|
          raise Px::Service::ServiceError.new("Error", 500)
        end

        subject.circuit_method(:test_method)
      end

      it "raises a ServiceError" do
        expect{
          subject.instance.test_method("test")
        }.to raise_error(Px::Service::ServiceError, "Error")
      end
    end

    context "when the wrapped method fails with another exception" do
      before :each do
        subject.send(:define_method, :test_method) do |arg|
          this_is_not_a_method # Raises NoMethodError
        end

        subject.circuit_method(:test_method)
      end

      it "raises a ServiceError" do
        expect{
          subject.instance.test_method("test")
        }.to raise_error(Px::Service::ServiceError)
      end
    end

    context "when the circuit is open" do
      before :each do
        subject.send(:define_method, :test_method) do |arg|
          "should not be called"
        end

        subject.circuit_method(:test_method)

        subject.instance.circuit_state.trip
      end

      it "raises a ServiceError" do
        expect{
          subject.instance.test_method("test")
        }.to raise_error(Px::Service::ServiceError)
      end
    end
  end
end
