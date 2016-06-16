module Px::Service::Client
  module HmacSigning
    extend ActiveSupport::Concern
    included do
      alias_method_chain :_make_request, :signing

      cattr_accessor :secret do
        DEFAULT_SECRET
      end

      cattr_accessor  :keyspan do
        DEFAULT_KEYSPAN
      end

      # Default config for signing
      config do |config|
        config.hmac_secret = DEFAULT_SECRET
        config.hmac_keyspan = DEFAULT_KEYSPAN
      end

      ##
      # DEPRECATED: Use .config (base class method) instead
      alias_method :hmac_signing, :config
    end

    module ClassMethods
      ##
      # Generate a nonce that's used to expire message after keyspan seconds
      def generate_signature(method, uri, query, body, timestamp)
        secret = self.config.hmac_secret
        keyspan = self.config.hmac_keyspan
        nonce = (timestamp - (timestamp % keyspan)) + keyspan
        data = "#{method.capitalize},#{uri},#{query},#{body},#{nonce.to_s}"
        digest = OpenSSL::Digest.new('sha256')
        digest = OpenSSL::HMAC.digest(digest, secret, data)
        return Base64.urlsafe_encode64(digest).strip()
      end
    end

    def _make_request_with_signing(method, uri, query: nil, headers: nil, body: nil, timeout: nil, stats_tags: [])
      timestamp = Time.now.to_i
      signature = self.class.generate_signature(method, uri, query, body, timestamp)

      headers = {} if headers.nil?
      headers.merge!("X-Service-Auth" => signature)
      headers.merge!("Timestamp" => timestamp)

      _make_request_without_signing(
          method,
          uri,
          query: query,
          headers: headers,
          body: body,
          timeout: timeout,
          stats_tags: stats_tags)
    end

  end
end
