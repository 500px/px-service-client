require 'spec_helper'

describe PxService::Client::Base do
  subject { PxService::Client::Base.send(:new) }
  let(:response) do
    Typhoeus::Response.new(
      code: 200,
      body: { status: 200, message: "Success"}.to_json,
      headers: { "Content-Type" => "application/json"} )
  end

  describe '#make_request' do
    let(:url) { 'http://localhost:3000/path' }

    it "returns a future response" do
      expect(subject.send(:make_request, 'get', url)).to be_a(PxService::Client::Future)
    end

    context "with a header" do
      let(:expected_headers) {
        {
          "Cookie" => "_hpx1=cookie",
        }
      }

      let(:resp) { subject.send(:make_request, 'get', url, headers: expected_headers) }
      let(:headers) { resp.request.options[:headers] }

      it "sets the expected header" do
        expect(headers).to include(expected_headers)
      end
    end

    context "with a query" do
      let(:expected_query) {
        {
          "one" => "a",
          "two" => "b",
        }
      }

      let(:resp) { subject.send(:make_request, 'get', url, query: expected_query) }

      it "sets the query" do
        expect(resp.request.url).to include("one=a&two=b")
      end
    end
  end
end
