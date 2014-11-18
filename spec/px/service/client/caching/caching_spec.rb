require 'spec_helper'
require 'dalli'

describe Px::Service::Client::Caching do
  subject {
    Class.new.include(Px::Service::Client::Caching).tap do |c|
      # Anonymous classes don't have a name.  Stub out :name so that things work
      allow(c).to receive(:name).and_return("Caching")
    end.new
  }

  let(:dalli_host) { "localhost:11211" }
  let(:dalli_options) { { :namespace => "service-client-test", expires_in: 3600, compress: false, failover: false } }
  let(:dalli) { Dalli::Client.new(dalli_host, dalli_options) }

  before :each do
    dalli.flush_all
    subject.cache_client = dalli
  end

  let (:url) { "http://search/foo?bar=baz"}
  let (:response) {
    { "response" => ["foo", "bar"], "status" => 200 }
  }

  shared_examples_for "a successful request" do
    it "should call the block" do
      called = false
      subject.cache_request(url, strategy: strategy) do |u|
        expect(u).to eq(url)
        called = true
      end

      expect(called).to be_truthy
    end

    it "should return the block's return value" do
      expect(subject.cache_request(url, strategy: strategy) { response }).to eq(response)
    end
  end

  shared_examples_for "a failed uncacheable request" do
    it "should raise the exception raised by the block" do
      expect{
        subject.cache_request(url, strategy: strategy) do
          # Px::Service::ServiceRequestError is not cachable
          # and does not trigger a fallback to a cached response
          raise Px::Service::ServiceRequestError.new("Error", 404)
        end
      }.to raise_error(Px::Service::ServiceRequestError)
    end
  end

  shared_examples_for "a request with no cached response" do
    it "raises the exception" do
      expect {
        subject.cache_request(url, strategy: strategy) do
          raise Px::Service::ServiceError.new("Error", 500)
        end
      }.to raise_error(Px::Service::ServiceError)
    end
  end

  context "when not caching" do
    let(:strategy) { :none }

    it_behaves_like "a successful request"
    it_behaves_like "a failed uncacheable request"
  end

  context "when caching as a last resort" do
    let(:strategy) { :last_resort }

    it_behaves_like "a successful request"
    it_behaves_like "a failed uncacheable request"

    context "when there is a cached response" do
      before :each do
        subject.cache_request(url, strategy: strategy) do
          response
        end
      end

      it "returns the cached response on failure" do
        expect(subject.cache_request(url, strategy: strategy) do
          raise Px::Service::ServiceError.new("Error", 500)
        end).to eq(response)
      end

      it "does not returns the cached response on request error" do
        expect {
          subject.cache_request(url, strategy: strategy) do
            raise Px::Service::ServiceRequestError.new("Error", 404)
          end
        }.to raise_error(Px::Service::ServiceRequestError)
      end

      it "touches the cache entry on failure" do
        expect(dalli).to receive(:touch).with(a_kind_of(String), a_kind_of(Fixnum))

        subject.cache_request(url, strategy: strategy) do
          raise Px::Service::ServiceError.new("Error", 500)
        end
      end
    end

    it_behaves_like "a request with no cached response"
  end

  context "when caching as a first resort" do
    let(:strategy) { :first_resort }

    it_behaves_like "a successful request"
    it_behaves_like "a failed uncacheable request"

    context "when there is a cached response" do
      before :each do
        subject.cache_request(url, strategy: strategy) do
          response
        end
      end

      it "does not invoke the block" do
        called = false
        subject.cache_request(url, strategy: strategy) do |u|
          called = true
        end

        expect(called).to be_falsey
      end

      it "returns the response" do
        expect(subject.cache_request(url, strategy: strategy) { nil }).to eq(response)
      end
    end

    context "when there is an expired cached response" do
      before :each do
        Timecop.freeze(10.minutes.ago) do
          subject.cache_request(url, strategy: strategy) do
            response
          end
        end
      end

      let (:response) { { "value" => "response" } }

      it "invokes the block" do
        called = false
        subject.cache_request(url, strategy: strategy) do |u|
          called = true
        end

        expect(called).to be_truthy
      end

      it "returns the new response" do
        expect(subject.cache_request(url, strategy: strategy) { response }).to eq(response)
      end

      it "updates the cache entry before making the request" do
        subject.cache_request(url, strategy: strategy) do
          # A bit goofy, but basically, make a request, but in the block
          # check that another request that happens while we're in the block
          # gets the cached result and doesn't invoke its own block
          called = false
          expect(subject.cache_request(url, strategy: strategy) do
            called = true
          end).to eq(response)
          expect(called).to be_falsey

          response
        end
      end

      it "caches the new response" do
        subject.cache_request(url, strategy: strategy) do
          response
        end

        expect(subject.cache_request(url, strategy: strategy) { nil }).to eq(response)
      end

      it "returns the cached response on failure" do
        expect(subject.cache_request(url, strategy: strategy) do
          raise Px::Service::ServiceError.new("Error", 500)
        end).to eq(response)
      end

      it "does not returns the cached response on request error" do
        expect {
          subject.cache_request(url, strategy: strategy) do
            raise Px::Service::ServiceRequestError.new("Error", 404)
          end
        }.to raise_error(Px::Service::ServiceRequestError)
      end

      it "touches the cache entry on failure" do
        expect(dalli).to receive(:touch).with(a_kind_of(String), a_kind_of(Fixnum)).twice

        subject.cache_request(url, strategy: strategy) do
          raise Px::Service::ServiceError.new("Error", 500)
        end
      end
    end

    it_behaves_like "a request with no cached response"
  end
end
