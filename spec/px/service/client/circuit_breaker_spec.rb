require 'spec_helper'

describe Px::Service::Client::CircuitBreaker do
  let(:subject_class) {
    Class.new do
      def make_request(method, uri, query: nil, headers: nil, body: nil, timeout: 0)
        Px::Service::Client::Future.new do
          _result
        end
      end
    end.tap do |c|
      # Anonymous classes don't have a name.  Stub out :name so that things work
      allow(c).to receive(:name).and_return("CircuitBreaker")
      c.include(Px::Service::Client::CircuitBreaker)
    end
  }

  subject { subject_class.new }

  describe '#included' do
    it "excludes Px::Service::ServiceRequestError by default" do
      expect(subject_class.circuit_handler.excluded_exceptions).to include(Px::Service::ServiceRequestError)
    end

    it "sets the failure threshold" do
      expect(subject_class.circuit_handler.failure_threshold).to eq(5)
    end

    it "sets the failure timeout" do
      expect(subject_class.circuit_handler.failure_timeout).to eq(7)
    end

    it "sets the invocation timeout" do
      expect(subject_class.circuit_handler.invocation_timeout).to eq(5)
    end
  end

  describe '#make_request' do
    context "when the wrapped method succeeds" do
      before :each do
        subject_class.send(:define_method, :_result) do
          "returned test"
        end
      end

      it "returns a Future" do
        expect(subject.make_request(:get, "http://test")).to be_a_kind_of(Px::Service::Client::Future)
      end

      it "returns the return value" do
        expect(subject.make_request(:get, "http://test").value!).to eq("returned test")
      end
    end

    context "when the wrapped method fails with a ServiceRequestError" do
      before :each do
        subject_class.send(:define_method, :_result) do
          raise Px::Service::ServiceRequestError.new("Error", 404)
        end
      end

      it "raises a ServiceRequestError" do
        expect{
          subject.make_request(:get, "http://test").value!
        }.to raise_error(Px::Service::ServiceRequestError, "Error")
      end
    end

    context "when the wrapped method fails with a ServiceError" do
      before :each do
        subject_class.send(:define_method, :_result) do
          raise Px::Service::ServiceError.new("Error", 500)
        end
      end

      it "raises a ServiceError" do
        expect{
          subject.make_request(:get, "http://test").value!
        }.to raise_error(Px::Service::ServiceError, "Error")
      end
    end

    context "when the circuit is open" do
      before :each do
        subject_class.send(:define_method, :_result) do
          "should not be called"
        end

        subject.circuit_state.trip
        subject.circuit_state.last_failure_time = Time.now
      end

      it "raises a ServiceError" do
        expect{
          subject.make_request(:get, "http://test").value!
        }.to raise_error(Px::Service::ServiceError)
      end
    end

    context "with multiple classes" do
      let(:other_class) {
        Class.new do
          def make_request(method, uri, query: nil, headers: nil, body: nil, timeout: 0)
            Px::Service::Client::Future.new do
              "result"
            end
          end
        end.tap do |c|
          # Anonymous classes don't have a name.  Stub out :name so that things work
          allow(c).to receive(:name).and_return("OtherCircuitBreaker")
          c.include(Px::Service::Client::CircuitBreaker)
        end
      }

      let(:other) { other_class.new }

      before :each do
        subject_class.send(:define_method, :_result) do
          "should not be called"
        end
      end

      context "when the breaker opens on the first instance" do
        before :each do
          subject.circuit_state.trip
          subject.circuit_state.last_failure_time = Time.now
        end

        it "raises a ServiceError on the first instance" do
          expect{
            subject.make_request(:get, "http://test").value!
          }.to raise_error(Px::Service::ServiceError)
        end

        it "does not raise a ServiceError on the second instance" do
          expect(other.make_request(:get, "http://test").value!).to eq("result")
        end
      end
    end

    context "with multiple instances of the same class" do
      let(:other) { subject_class.new }

      before :each do
        subject_class.send(:define_method, :_result) do
          "should not be called"
        end
      end

      context "when the breaker opens on the first instance" do
        before :each do
          subject.circuit_state.trip
          subject.circuit_state.last_failure_time = Time.now
        end

        it "raises a ServiceError on the first instance" do
          expect{
            subject.make_request(:get, "http://test").value!
          }.to raise_error(Px::Service::ServiceError)
        end

        it "raises a ServiceError on the second instance" do
          expect{
            other.make_request(:get, "http://test").value!
          }.to raise_error(Px::Service::ServiceError)
        end
      end
    end

  end
end
