module Px::Service::Client
  class Base
    cattr_accessor :logger

    def initialize(secret = 'dev', keyspan = 300)
      @secret = secret
      @keyspan = keyspan
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
        logger.debug "Completed request #{method.to_s.upcase} #{uri}, took #{elapsed.to_i}ms, got status #{response.response_code}" if logger
      end

      RetriableResponseFuture.new(req)
    end

    ##
    # Generate a timestamp nonce that's used to expire message after keyspan seconds
    def generate_signature(method, path, query, body)
      t = Time.now.to_i
      nonce = (t - (t % @keyspan)) + @keyspan

      instance = OpenSSL::HMAC.new(@secret, OpenSSL::Digest.new('sha256'))
      instance << method.capitalize
      instance << path
      instance << query
      instance << body
      instance << nonce.to_s

      Base64.urlsafe_encode64(instance.digest())
    end
  end
end
