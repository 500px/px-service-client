require 'spec_helper'

describe Px::Service::Client::CircuitBreaker do
  let(:subject_class) {
    Class.new(Px::Service::Client::Base).tap do |c|
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
    let(:url) { "http://test" }
    let(:multi) { Px::Service::Client::Multiplexer.new }
    let(:response) do
      Typhoeus::Response.new(
        code: 200,
        body: { status: 200, message: "Success" }.to_json,
        headers: { "Content-Type" => "application/json"} )
    end

    let(:request) do
      req = @object.send(:make_request, 'get', url)

      multi.context do
        multi.do(req)
      end.run

      req
    end

    before :each do
      @object = subject
      Typhoeus.stub(url).and_return(response)
    end

    context "when the underlying request method succeeds" do
      it "returns a RetriableResponseFuture" do
        expect(subject.send(:make_request, 'get', url)).to be_a_kind_of(Px::Service::Client::RetriableResponseFuture)
      end

      it "returns the return value" do
        expect(request.value!).to eq(response)
      end

      context "when the breaker is open" do
        before :each do
          allow(subject_class.circuit_handler).to receive(:is_timeout_exceeded).and_return(true)

          subject.circuit_state.trip
          subject.circuit_state.last_failure_time = Time.now
          subject.circuit_state.failure_count = 5
        end

        it "resets the failure count of the breaker" do
          expect {
            request.value!
          }.to change{subject.class.circuit_state.failure_count}.to(0)
        end

        it "closes the breaker" do
          expect {
            request.value!
          }.to change{subject.class.circuit_state.closed?}.from(false).to(true)
        end
      end
    end

    context "when the wrapped method fails with a ServiceRequestError" do
      let(:response) do
        Typhoeus::Response.new(
          code: 404,
          body: { status: 404, error: "Not Found"}.to_json,
          headers: { "Content-Type" => "application/json"} )
      end

      it "raises a ServiceRequestError" do
        expect {
          request.value!
        }.to raise_error(Px::Service::ServiceRequestError, "Not Found")
      end

      it "does not increment the failure count of the breaker" do
        expect {
          request.value! rescue nil
        }.not_to change{subject.class.circuit_state.failure_count}
      end
    end

    context "when the wrapped method fails with a ServiceError" do
      let(:response) do
        Typhoeus::Response.new(
          code: 500,
          body: { status: 500, error: "Error"}.to_json,
          headers: { "Content-Type" => "application/json"} )
      end

      it "raises a ServiceError" do
        expect {
          request.value!
        }.to raise_error(Px::Service::ServiceError, "Error")
      end

      it "increments the failure count of the breaker" do
        expect {
          request.value! rescue nil
        }.to change{subject.class.circuit_state.failure_count}.by(4) # 1 + 3 retries
      end
    end

    context "when the circuit is open" do
      before :each do
        subject.circuit_state.trip
        subject.circuit_state.last_failure_time = Time.now
      end

      it "raises a ServiceError" do
        expect {
          request.value!
        }.to raise_error(Px::Service::ServiceError)
      end
    end

    context "with multiple classes" do
      let(:other_class) {
        Class.new(Px::Service::Client::Base).tap do |c|
          # Anonymous classes don't have a name.  Stub out :name so that things work
          allow(c).to receive(:name).and_return("OtherCircuitBreaker")
          c.include(Px::Service::Client::CircuitBreaker)
        end
      }

      let(:other) { other_class.new }

      context "when the breaker opens on the first instance" do
        before :each do
          subject.circuit_state.trip
          subject.circuit_state.last_failure_time = Time.now
        end

        it "raises a ServiceError on the first instance" do
          expect {
            request.value!
          }.to raise_error(Px::Service::ServiceError)
        end

        it "does not raise a ServiceError on the second instance" do
          @object = other
          expect(request.value!).to eq(response)
        end
      end
    end

    context "with multiple instances of the same class" do
      let(:other) { subject_class.new }

      context "when the breaker opens on the first instance" do
        before :each do
          subject.circuit_state.trip
          subject.circuit_state.last_failure_time = Time.now
        end

        it "raises a ServiceError on the first instance" do
          expect {
            request.value!
          }.to raise_error(Px::Service::ServiceError)
        end

        it "raises a ServiceError on the second instance" do
          @object = other
          expect {
            request.value!
          }.to raise_error(Px::Service::ServiceError)
        end
      end
    end

  end
end
