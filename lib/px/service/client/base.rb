module Px::Service::Client
  class Base
    cattr_accessor :logger

    class DefaultConfig < OpenStruct
      def initialize
        super
        self.statsd_client = NullStatsdClient.new
      end
    end

    ##
    # Configure the client
    def self.config
      @config ||= DefaultConfig.new
      yield(@config) if block_given?
      @config
    end

    # Make class config available to instances
    def config
      if block_given?
        self.class.config { |c| yield(c) }
      else
        self.class.config
      end
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
    def make_request(method, uri, query: nil, headers: nil, body: nil, timeout: 0)
      stats_tags = [
        "method:#{method.downcase}",
      ]
      if uri.respond_to?(:path)
        stats_tags << "host:#{uri.host}"
        stats_tags << "path:#{uri.path}"
      else
        actual_uri = URI(uri)
        stats_tags << "host:#{actual_uri.host}"
        stats_tags << "path:#{actual_uri.path}"
      end

      _make_request(method, uri, query: query, headers: headers, body: body, timeout: timeout, stats_tags: stats_tags)
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
