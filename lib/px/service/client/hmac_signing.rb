module Px::Service::Client
  module HmacSigning
    extend ActiveSupport::Concern

    @@secret = ENV['PX_HMAC_SECRET_KEY']
    @@keyspan = 300

    included do
      alias_method_chain :make_request, :signing
    end

    def make_request_with_signing(method, uri, query: nil, headers: nil, body: nil)

      signature, timestamp, nonce = generate_signature(method, uri, query, body)
      headers = {} if headers.nil?
      headers.merge!("Timestamp" => timestamp)
      headers.merge!("Nonce" => nonce)
      headers.merge!("Signature" => signature)

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
      t = Time.now.to_i
      nonce = (t - (t % @@keyspan)) + @@keyspan
      data = "#{method.capitalize},#{uri},#{query},#{body},#{nonce.to_s}"
      digest = OpenSSL::Digest.new('sha256')
      cypher = OpenSSL::HMAC.digest(digest, @@secret, data)
      
      return Base64.urlsafe_encode64(cypher).strip(), t, nonce
    end

  end
end
