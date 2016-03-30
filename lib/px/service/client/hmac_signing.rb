module Px::Service::Client
  module HmacSigning
    extend ActiveSupport::Concern
    
    included do
      alias_method_chain :make_request, :signing
    end

    def make_request_with_signing(method, uri, query: nil, headers: nil, body: nil)

      signature = generate_signature(method, uri, query, body)
      headers = {} if headers.nil?
      headers.merge!("X-Service-Auth" => signature)

      make_request_without_signing(
          method,
          uri,
          query: query,
          headers: headers,
          body: body)
    end

    ##
    # Generate a timestamp, a nonce and the corresponding HMAC signature
    def generate_signature(method, uri, query, body)
      keyspan = Px::Service::Client.config.keyspan
      secret = Px::Service::Client.config.secret
      t = Time.now.to_i
      nonce = (t - (t % keyspan)) + keyspan
      data = "#{method.capitalize},#{uri},#{query},#{body},#{nonce.to_s}"
      digest = OpenSSL::Digest.new('sha256')
      digest = OpenSSL::HMAC.digest(digest, secret, data)
      
      return Base64.urlsafe_encode64(digest).strip()
    end

  end
end
