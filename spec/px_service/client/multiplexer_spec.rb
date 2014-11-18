require 'spec_helper'

describe PxService::Client::Multiplexer do
  let(:client) { PxService::Client::Base.send(:new) }

  context '.new' do
    it 'should work with no argments' do
      expect {
        PxService::Client::Multiplexer.new
      }.not_to raise_error
    end
  end

  context 'with one request', vcr: true do
    let(:req1) { client.send(:make_request, :get, 'http://localhost:3000/status') }

    it "returns a ResponseFuture" do
      subject.context do
        resp1 = subject.do(req1)

        expect(resp1).to be_a(PxService::Client::RetriableResponseFuture)
      end.run
    end

    it "runs the requests" do
      subject.context do
        resp1 = subject.do(req1)

        expect(resp1.body).to eq("OK")
      end.run
    end
  end

  context 'with multiple requests', vcr: true do
    let(:req1) { client.send(:make_request, :get, 'http://localhost:3000/status') }
    let(:req2) { client.send(:make_request, :get, 'http://localhost:3000/status') }

    context "when the requests don't depend on each other" do
      it "runs the requests" do
        subject.context do
          resp1 = subject.do(req1)
          resp2 = subject.do(req2)

          expect(resp2.body).to eq("OK")
          expect(resp1.body).to eq("OK")
        end.run
      end
    end

    context "when the requests depend on each other" do
      it "runs the requests" do
        subject.context do
          resp1 = subject.do(req1)
          client.send(:make_request, :get, "http://localhost:3000/status?#{resp1.body}")
          resp2 = subject.do(req2)

          expect(resp2.body).to eq("OK")
          expect(resp1.body).to eq("OK")
        end.run
      end
    end
  end
end
