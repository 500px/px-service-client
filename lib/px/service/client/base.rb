module Px::Service::Client
  class Base
    class_attribute :logger, :config

    class DefaultConfig < OpenStruct
      def initialize
        super
        self.statsd_client = NullStatsdClient.new
      end
    end

    self.config = DefaultConfig.new

    ##
    # Configure the client
    def self.configure
      c = self.config.dup
      yield(c) if block_given?
      self.config = c
    end

    # Make class config available to instances
    def configure
      self.class.configure { |c| yield(c) }
    end

    private

    def parsed_body(response)
      if response.success?
        Hashie::Mash.new(JSON.parse(response.body))
      else
        if response.response_headers["Content-Type"] =~ %r{application/json}
          JSON.parse(response.body)["error"] rescue response.body.try(:strip)
        else
          response.body.strip
        end
      end
    end

    ##
    # Make the request
    def make_request(method, uri, query: nil, headers: nil, body: nil, timeout: 0, stats_tags: [])
      _stats_tags = [
        "remote_method:#{method.downcase}",
      ].concat(stats_tags)

      if uri.respond_to?(:host)
        _stats_tags << "remote_host:#{uri.host.downcase}"
      else
        actual_uri = URI(uri)
        _stats_tags << "remote_host:#{actual_uri.host.downcase}"
      end

      _make_request(method, uri, query: query, headers: headers, body: body, timeout: timeout, stats_tags: _stats_tags)
    end

    def _make_request(method, uri, query: nil, headers: nil, body: nil, timeout: nil, stats_tags: [])
      req = Typhoeus::Request.new(
        uri,
        method: method,
        params: query,
        body: body,
        headers: headers,
        timeout: timeout)

      start_time = Time.now
      logger.debug "Making request #{method.to_s.upcase} #{uri}" if logger

      req.on_complete do |response|
        elapsed = (Time.now - start_time) * 1000
        config.statsd_client.histogram("request.duration", elapsed.to_i, tags: stats_tags)
        config.statsd_client.increment("response.count", tags: stats_tags + ["httpstatus:#{response.response_code}"])
        case
        when response.response_code > 100 && response.response_code < 199
          config.statsd_client.increment("response.status_1xx.count", tags: stats_tags)
        when response.response_code > 200 && response.response_code < 299
          config.statsd_client.increment("response.status_2xx.count", tags: stats_tags)
        when response.response_code > 300 && response.response_code < 399
          config.statsd_client.increment("response.status_3xx.count", tags: stats_tags)
        when response.response_code > 400 && response.response_code < 499
          config.statsd_client.increment("response.status_4xx.count", tags: stats_tags)
        when response.response_code > 500
          config.statsd_client.increment("response.status_5xx.count", tags: stats_tags)
        end
        logger.debug "Completed request #{method.to_s.upcase} #{uri}, took #{elapsed.to_i}ms, got status #{response.response_code}" if logger
      end

      RetriableResponseFuture.new(req)
    end


  end
end
