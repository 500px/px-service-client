require 'spec_helper'

describe PxService::Client::RetriableResponseFuture do
  let(:request) { Typhoeus::Request.new('http://localhost:3000/status') }
  let(:response) do
    Typhoeus::Response.new(
      code: 200,
      body: { status: 200, message: "Success"}.to_json,
      headers: { "Content-Type" => "application/json"} )
  end
  let(:hydra) { Typhoeus::Hydra.new }
  subject { PxService::Client::RetriableResponseFuture.new(request) }

  before :each do
    Typhoeus.stub(/status/).and_return(response)
  end

  describe '#hydra=' do
    it "queues the request on the hydra" do
      expect(hydra).to receive(:queue).with(request)

      subject.hydra = hydra
    end
  end

  describe '#method_missing' do
    context "when the request is still in progress" do
      it "does not call the method on the response" do
        Fiber.new do
          expect(response).not_to receive(:body)

          subject.hydra = hydra

          subject.body
        end.resume
      end
    end

    context "when the request status is an error" do
      let(:response) do
        Typhoeus::Response.new(
          code: 500,
          body: { status: 500, error: "Failed"}.to_json,
          headers: { "Content-Type" => "application/json"} )
      end

      it "completes the future only once" do
        Fiber.new do
          expect {
            subject.total_time
          }.to raise_error(PxService::ServiceError, "Failed")
        end.resume

        Fiber.new do
          subject.hydra = hydra
          hydra.run
        end.resume
      end

      it "retries the request" do
        f = PxService::Client::RetriableResponseFuture.new(retries: 3)

        Fiber.new do
          expect {
            f.response_code
          }.to raise_error(PxService::ServiceError, "Failed")
        end.resume

        Fiber.new do
          expect(hydra).to receive(:queue).with(request).exactly(4).times.and_call_original
          f.request = request

          f.hydra = hydra
          hydra.run
        end.resume
      end
    end

    context "when the request completes" do
      it "calls any pending methods on the response" do
        expect(response).to receive(:total_time)
        called = false

        Fiber.new do
          subject.total_time
          called = true
        end.resume

        Fiber.new do
          subject.hydra = hydra
          hydra.run
        end.resume

        expect(called).to eq(true)
      end
    end
  end

end
