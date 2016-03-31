module Px::Service::Client
  module HmacSigning
    extend ActiveSupport::Concern
    included do
      alias_method_chain :make_request, :signing
      
      cattr_accessor :secret do
        DEFAULT_SECRET
      end
      
      cattr_accessor  :keyspan do
        DEFAULT_KEYSPAN
      end
      
    end   

    module ClassMethods      
      DefaultConfig = Struct.new(:secret, :keyspan) do
        def initialize
          self.secret = DEFAULT_SECRET
          self.keyspan = DEFAULT_KEYSPAN
        end
      end

      # initialize the config variables (including secret, keyspan) for hmac siging
      def hmac_signing(&block)
        @signing_config = DefaultConfig.new
        
        # use default config if no block is given
        if block_given?
          yield(@signing_config)        
          self.secret = @signing_config.secret
          self.keyspan = @signing_config.keyspan
        end
      end
      
      ##
      # Generate a nonce that's used to expire message after keyspan seconds
      def generate_signature(method, uri, query, body, timestamp)
        secret = self.secret
        keyspan = self.keyspan
        nonce = (timestamp - (timestamp % keyspan)) + keyspan
        data = "#{method.capitalize},#{uri},#{query},#{body},#{nonce.to_s}"
        digest = OpenSSL::Digest.new('sha256')
        digest = OpenSSL::HMAC.digest(digest, secret, data)
        return Base64.urlsafe_encode64(digest).strip()
      end
    end
    
    def make_request_with_signing(method, uri, query: nil, headers: nil, body: nil)
      timestamp = Time.now.to_i
      signature = self.class.generate_signature(method, uri, query, body, timestamp)
      
      headers = {} if headers.nil?
      headers.merge!("X-Service-Auth" => signature)
      headers.merge!("Timestamp" => timestamp)

      make_request_without_signing(
          method,
          uri,
          query: query,
          headers: headers,
          body: body)
    end

  end
end
