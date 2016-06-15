require 'spec_helper'
require 'dalli'

describe Px::Service::Client::Caching do
  let(:dalli_host) { ENV['PX_MEMCACHED_HOST'] }
  let(:dalli_options) { { :namespace => "service-client-test", expires_in: 3600, compress: false, failover: false } }
  let(:dalli) { Dalli::Client.new(dalli_host, dalli_options) }

  subject {
    Class.new.include(Px::Service::Client::Caching).tap do |c|
      # Anonymous classes don't have a name.  Stub out :name so that things work
      allow(c).to receive(:name).and_return("Caching")

      c.caching do |config|
        config.cache_client = dalli
      end
    end.new
  }

  let (:url) { "http://search/foo?bar=baz" }
  let(:multi) { Px::Service::Client::Multiplexer.new }
  let(:request) { Typhoeus::Request.new(url, method: :get) }
  let(:future) { Px::Service::Client::RetriableResponseFuture.new(request) }
  let(:response) do
    Typhoeus::Response.new(
      code: 200,
      body: { status: 200, message: "Success" }.to_json,
      headers: { "Content-Type" => "application/json"} )
  end
  let(:entry) { Px::Service::Client::Caching::CacheEntry.new(dalli, url, 'general', response.options) }
  let(:strategy) { :none }

  before :each do
    dalli.flush_all
    Typhoeus.stub(url).and_return(response)
  end

  shared_examples_for "a successful request" do
    it "should call the block" do
      called = false
      subject.cache_request(url, strategy: strategy) do
        Px::Service::Client::Future.new { called = true }
      end

      expect(called).to be_truthy
    end

    it "should return the block's return value" do
      expect(subject.cache_request(url, strategy: strategy) do
        resp = nil
        multi.context do
          resp = multi.do(future)
        end.run

        resp
      end.value!.options).to eq(response.options)
    end
  end

  shared_examples_for "a failed uncacheable request" do
    it "should raise the exception raised by the block" do
      expect {
        subject.cache_request(url, strategy: strategy) do
          # Px::Service::ServiceRequestError is not cachable
          # and does not trigger a fallback to a cached response
          raise Px::Service::ServiceRequestError.new("Error", 404)
        end.value!
      }.to raise_error(Px::Service::ServiceRequestError)
    end
  end

  shared_examples_for "a request with no cached response" do
    it "raises the exception" do
      expect { 
        subject.cache_request(url, strategy: strategy) do
          raise Px::Service::ServiceError.new("Error", 500)
        end.value!
      }.to raise_error(Px::Service::ServiceError)
    end
  end

  context "when not caching" do
    it_behaves_like "a successful request"
    it_behaves_like "a failed uncacheable request"

    context 'when cache client is not set' do
      before :each do
        subject.class.caching do |config|
          config.cache_client = nil
        end
      end

      it 'does not raise an exception' do
        expect {
          subject.cache_request(url, strategy: strategy) do
            nil
          end
        }.to_not raise_error
      end
    end
  end

  context "when caching as a last resort" do
    let(:strategy) { :last_resort }

    it_behaves_like "a successful request"
    it_behaves_like "a failed uncacheable request"

    context "when there is a cached response" do
      context 'when cache client is not set' do
        before :each do
          subject.class.caching do |config|
            config.cache_client = nil
          end
        end

        it 'raises an argument exception' do
          expect {
            subject.cache_request(url, strategy: strategy) do
              Px::Service::Client::Future.new { raise Px::Service::ServiceError.new("Error", 500) }
            end.value!
          }.to raise_error(ArgumentError)
        end
      end

      context 'when the cache client is set' do
        before :each do
          Px::Service::Client::Caching::CacheEntry.stub(:fetch).and_return(entry)
        end

        it "returns the cached response on failure" do
          expect(subject.cache_request(url, strategy: strategy) do
            Px::Service::Client::Future.new { raise Px::Service::ServiceError.new("Error", 500) }
          end.value!).to eq(response.options)
        end

        it "does not returns the cached response on request error" do
          expect {
            subject.cache_request(url, strategy: strategy) do
              Px::Service::Client::Future.new { raise Px::Service::ServiceRequestError.new("Error", 404) }
            end.value!
          }.to raise_error(Px::Service::ServiceRequestError)
        end

        it "touches the cache entry on failure" do
          expect(dalli).to receive(:touch).with(a_kind_of(String), a_kind_of(Fixnum))

          subject.cache_request(url, strategy: strategy) do
            Px::Service::Client::Future.new { raise Px::Service::ServiceError.new("Error", 500) }
          end
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
      context 'when cache client is not set' do
        before :each do
          subject.class.caching do |config|
            config.cache_client = nil
          end
        end

        it 'raises an argument exception' do
          expect {
            subject.cache_request(url, strategy: strategy) do
              nil
            end.value!
          }.to raise_error(ArgumentError)
        end
      end

      context 'when the cache client is set' do
        before :each do
          Px::Service::Client::Caching::CacheEntry.stub(:fetch).and_return(entry)
          entry.expires_at = DateTime.now + 1.day
        end

        it "does not invoke the block" do
          called = false
          subject.cache_request(url, strategy: strategy) do
            called = true
          end

          expect(called).to be_falsey
        end

        it "returns the response" do
          expect(subject.cache_request(url, strategy: strategy) do
            Future.new do
              nil
            end
          end.value!).to eq(response.options)
        end
      end
    end

    context "when there is an expired cached response" do
      before :each do
        Px::Service::Client::Caching::CacheEntry.stub(:fetch).and_return(entry)
        entry.expires_at = DateTime.now - 1.day
      end

      let(:response) do
        Typhoeus::Response.new(
          code: 200,
          body: { status: 200, message: "New response" }.to_json,
          headers: { "Content-Type" => "application/json"} )
      end

      it "invokes the block" do
        called = false
        subject.cache_request(url, strategy: strategy) do |u|
          Px::Service::Client::Future.new do
            called = true
            { stub: "stub str" }.to_hash
          end
        end

        expect(called).to be_truthy
      end

      it "returns the new response" do
        result = subject.cache_request(url, strategy: strategy) do
          resp = nil
          multi.context do
            resp = multi.do(future)
          end.run

          resp
        end.value!

        body = JSON.parse(result.body)

        expect(body[:message]).to eq(JSON.parse(response.body)[:message])
      end

      it "updates the cache entry before making the request" do
        subject.cache_request(url, strategy: strategy) do
          # A bit goofy, but basically, make a request, but in the block
          # check that another request that happens while we're in the block
          # gets the cached result and doesn't invoke its own block
          called = false
          expect(subject.cache_request(url, strategy: strategy) do
            called = true
            resp = nil
            multi.context do
              resp = multi.do(future)
            end.run

            resp
          end.value!).to eq(response.options)

          expect(called).to be_falsey

          response
        end
      end

      it "caches the new response" do
        subject.cache_request(url, strategy: strategy) do
          resp = nil
          multi.context do
            resp = multi.do(future)
          end.run

          resp
        end

        expect(subject.cache_request(url, strategy: strategy) do
          nil
        end.value).to eq(response.options)
      end

      it "returns the cached response on failure" do
        expect(subject.cache_request(url, strategy: strategy) do
          Px::Service::Client::Future.new { raise Px::Service::ServiceError.new("Error", 500) }
        end.value!).to eq(response.options)
      end

      it "does not returns the cached response on request error" do
        expect {
          subject.cache_request(url, strategy: strategy) do
            Px::Service::Client::Future.new { raise Px::Service::ServiceRequestError.new("Error", 404) }
          end.value!
        }.to raise_error(Px::Service::ServiceRequestError)
      end

      it "touches the cache entry on failure" do
        expect(dalli).to receive(:touch).with(a_kind_of(String), a_kind_of(Fixnum)).twice

        subject.cache_request(url, strategy: strategy) do
          Px::Service::Client::Future.new { raise Px::Service::ServiceError.new("Error", 500) }
        end
      end
    end

    it_behaves_like "a request with no cached response"
  end
end
