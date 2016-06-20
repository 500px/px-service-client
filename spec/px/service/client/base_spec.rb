require 'spec_helper'

describe Px::Service::Client::Base do
  let(:dalli_host) { ENV['PX_MEMCACHED_HOST'] }
  let(:dalli_options) { { :namespace => "service-client-test", expires_in: 3600, compress: false, failover: false } }
  let(:dalli) { Dalli::Client.new(dalli_host, dalli_options) }

  subject {
    Class.new(Px::Service::Client::Base).tap do |c|
      c.include(Px::Service::Client::Caching)
      c.config do |config|
        config.cache_client = dalli
      end
    end.new
  }

  let(:successful_response) do
    Typhoeus::Response.new(
      code: 200,
      body: { status: 200, message: "Success" }.to_json,
      headers: { "Content-Type" => "application/json"} )
  end

  describe '#config' do
    let(:other_subclass) {
      Class.new(Px::Service::Client::Base).tap do |c|
        c.include(Px::Service::Client::Caching)
      end.new
    }

    context "when there are separate subclasses" do
      before :each do
        subject.config do |c|
          c.subject_field = "value"
        end
      end

      it "sets the config value on the subject" do
        expect(subject.config.subject_field).to eq("value")
      end

      it "does not set the config value on other subclasses" do
        expect(other_subclass.config.subject_field).not_to eq("value")
      end
    end
  end

  describe '#make_request' do
    let(:url) { 'http://localhost:3000/path' }

    it "returns a future response" do
      expect(subject.send(:make_request, 'get', url)).to be_a(Px::Service::Client::Future)
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

    context "when the caching strategy is set" do
      let(:multi) { Px::Service::Client::Multiplexer.new }
      let(:request) { Typhoeus::Request.new(url, method: :get) }
      let(:future) { Px::Service::Client::RetriableResponseFuture.new(request) }

      before :each do
        dalli.flush_all
        Typhoeus.stub(url).and_return(response)
      end

      shared_examples_for 'a request that returns a cached response body' do
        let(:cache_entry) { Px::Service::Client::Caching::CacheEntry.new(dalli, url, 'general', response.body, Time.now + 1.year) }

        before :each do
          Typhoeus::Expectation.clear
          Typhoeus.stub(url).and_return(successful_response)

          req = subject.send(:make_request, 'get', url)
          subject.cache_request(req.request.url, strategy: strategy) do
            resp = nil
            multi.context do
              resp = multi.do(req)
            end.run

            Px::Service::Client::Future.new do
              resp.options[:body]
            end
          end
        end

        it 'does not return a new response' do
          req = subject.send(:make_request, 'get', url)

          expect(Px::Service::Client::RetriableResponseFuture).to_not receive(:new)
          subject.cache_request(req.request.url, strategy: strategy) do
            resp = nil
            multi.context do
              resp = multi.do(req)
            end.run

            Px::Service::Client::Future.new do
              resp.options[:body]
            end
          end
        end

        it 'returns the cached response body' do
          Typhoeus::Expectation.clear
          Typhoeus.stub(url).and_return(response)
          req = subject.send(:make_request, 'get', url)
          subject.cache_request(req.request.url, strategy: strategy) do
            resp = nil

            multi.context do
              resp = multi.do(req)
              expect(resp.options[:body]).to eq(cache_entry.data)
            end

            Px::Service::Client::Future.new do
              resp.options[:body]
            end
          end
        end
      end

      context 'to first_resort' do
        let(:strategy) { :first_resort }
        let(:response) { successful_response }

        it_behaves_like 'a request that returns a cached response body'

        context 'when the request fails' do
          let(:response) do
            Typhoeus::Response.new(
              code: 500,
              body: { status: 500, error: "Failed"}.to_json,
              headers: { "Content-Type" => "application/json"} )
          end

          context 'when no response is cached' do
            it 'makes the request' do
              called = false
              req = subject.send(:make_request, 'get', url)

              subject.cache_request(req.request.url, strategy: strategy) do
                resp = nil
                multi.context do
                  resp = multi.do(req)
                  called = true
                end.run

                Px::Service::Client::Future.new do
                  resp.options[:body]
                end
              end

              expect(called).to be_truthy
            end

            it 'returns an error' do
              req = subject.send(:make_request, 'get', url)
              expect {
                subject.cache_request(req.request.url, strategy: strategy) do
                  resp = nil
                  multi.context do
                    resp = multi.do(req)
                  end.run

                  Px::Service::Client::Future.new do
                    resp.options[:body]
                  end
                end.value!
              }.to raise_error(Px::Service::ServiceError, 'Failed')
            end
          end

          context 'when a response has been cached' do
            it_behaves_like 'a request that returns a cached response body'
          end
        end
      end

      context 'to last_resort' do
        let(:strategy) { :last_resort }
        let(:response) { successful_response }

        it 'makes the request' do
          called = false
          req = subject.send(:make_request, 'get', url)

          subject.cache_request(req.request.url, strategy: strategy) do
            resp = nil
            multi.context do
              resp = multi.do(req)
              called = true
            end.run

            Px::Service::Client::Future.new do
              resp.options[:body]
            end
          end

          expect(called).to be_truthy
        end

        context 'when the request fails' do
          let(:response) do
            Typhoeus::Response.new(
              code: 500,
              body: { status: 500, error: "Failed"}.to_json,
              headers: { "Content-Type" => "application/json"} )
          end

          context 'when no response is cached' do
            it 'makes the request' do
              called = false
              req = subject.send(:make_request, 'get', url)

              subject.cache_request(req.request.url, strategy: strategy, refresh_probability: 0) do
                resp = nil
                multi.context do
                  resp = multi.do(req)
                  called = true
                end.run

                Px::Service::Client::Future.new do
                  resp.options[:body]
                end
              end

              expect(called).to be_truthy
            end

            it 'raises an error' do
              req = subject.send(:make_request, 'get', url)

              expect {
                subject.cache_request(req.request.url, strategy: strategy) do
                  resp = nil
                  multi.context do
                    resp = multi.do(req)
                  end.run

                  Px::Service::Client::Future.new do
                    resp.options[:body]
                  end
                end.value!
              }.to raise_error(Px::Service::ServiceError, 'Failed')
            end
          end

          context 'when a response body has been cached' do
            before :each do
              Typhoeus::Expectation.clear
              Typhoeus.stub(url).and_return(successful_response)

              req = subject.send(:make_request, 'get', url)

              subject.cache_request(req.request.url, strategy: strategy) do
                resp = nil
                multi.context do
                  resp = multi.do(req)
                end.run

                Px::Service::Client::Future.new do
                  resp.options[:body]
                end
              end
            end

            it 'makes the request' do
              called = false
              req = subject.send(:make_request, 'get', url)
              subject.cache_request(req.request.url, strategy: strategy) do
                resp = nil
                multi.context do
                  resp = multi.do(req)
                  called = true
                end.run

                Px::Service::Client::Future.new do
                  resp.options[:body]
                end
              end

              expect(called).to be_truthy
            end

            it 'returns the cached response body' do
              Typhoeus::Expectation.clear
              Typhoeus.stub(url).and_return(response)
              req = subject.send(:make_request, 'get', url)

              expect(subject.cache_request(req.request.url, strategy: strategy) do
                resp = nil
                multi.context do
                  resp = multi.do(req)
                end.run

                Px::Service::Client::Future.new do
                  resp.options[:body]
                end
              end.value!['status']).to be(200)
            end
          end

        end
      end
    end
  end
end
