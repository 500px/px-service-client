require 'active_support'
require 'active_support/core_ext'
require 'service/errors'

module Service
  module Client
    def request_headers
      {}
    end
  end
end

require "service/client/version"
require "service/client/caching"
require "service/client/list_response"
require "service/client/circuit_breaker"
