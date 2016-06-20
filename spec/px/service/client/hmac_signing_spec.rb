require 'spec_helper'

describe Px::Service::Client::HmacSigning do
  let(:subject_class) {
    Class.new(Px::Service::Client::Base).tap do |c|
      # Anonymous classes don't have a name.  Stub out :name so that things work
      allow(c).to receive(:name).and_return("HmacSigning")
      c.include(Px::Service::Client::HmacSigning)
    end
  }

  let(:another_class) {
    Class.new(Px::Service::Client::Base).tap do |c|
      c.include(Px::Service::Client::HmacSigning)

      c.config do |config|
        config.hmac_secret = "different secret"
      end
    end
  }

  subject { subject_class.new }
  let(:another_object) { another_class.new }

  describe '#make_request' do
    context "when the underlying request method succeeds" do
      let(:url) { 'http://localhost:3000/path' }
      let(:resp) { subject.send(:make_request, 'get', url) }
      let(:headers) { resp.request.options[:headers] }

      it "returns a Future" do
        expect(resp).to be_a_kind_of(Px::Service::Client::RetriableResponseFuture)
      end

      it "contains a header with auth signature" do
        expect(headers).to have_key("X-Service-Auth")
        expect(headers).to have_key("Timestamp")
      end

      let(:resp2) { another_object.send(:make_request, 'get', url) }
      let(:headers2) { resp2.request.options[:headers] }
      it "is different from the object of another class with a different key" do
        expect(headers["X-Service-Auth"]).not_to eq(headers2["X-Service-Auth"])
      end
    end
  end
end
