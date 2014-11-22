# This is based on this code: https://github.com/bitherder/stitch

require 'fiber'

module Px::Service::Client
  class RetriableResponseFuture < Future
    DEFAULT_RETRIES = 3

    attr_reader :hydra, :request

    def initialize(request = nil, retries: DEFAULT_RETRIES)
      super()

      @retries = retries
      self.request = request if request
    end

    def request=(request)
      raise ArgumentError.new("A request has already been assigned") if @request

      @request = request
      self.request.on_complete do |response|
        result = handle_error_statuses(response)
        complete(result)
      end

      configure_auto_retry(request, @retries)

      hydra.queue(request) if hydra
    end

    def hydra=(hydra)
      raise ArgumentError.new("A hydra has already been assigned") if @hydra

      @hydra = hydra
      hydra.queue(request) if request
    end

    private

    ##
    # Raise appropriate exception on error statuses
    def handle_error_statuses(response)
      return response if response.success?

      begin
        body = parse_error_body(response)

        if response.response_code >= 400 && response.response_code < 499
          raise Px::Service::ServiceRequestError.new(body, response.response_code)
        elsif response.response_code >= 500 || response.response_code == 0
          raise Px::Service::ServiceError.new(body, response.response_code)
        end
      rescue Exception => ex
        return ex
      end
    end

    def parse_error_body(response)
      if response.headers && response.headers["Content-Type"] =~ %r{application/json}
        JSON.parse(response.body)["error"] rescue response.body.try(:strip)
      else
        response.body.strip
      end
    end


    ##
    # Configures auto-retry on the request
    def configure_auto_retry(request, retries)
      return if retries.nil? || retries == 0
      # To do this, we have to hijack the Typhoeus callback list, as there's
      # no way to prevent later callbacks from being executed from earlier callbacks
      old_on_complete = request.on_complete.dup
      request.on_complete.clear
      retries_left = retries

      request.on_complete do |response|
        if !self.completed?
          if response.success? || retries_left <= 0
            # Call the old callbacks
            old_on_complete.map do |callback|
              response.handled_response = callback.call(response)
            end
          else
            # Retry
            retries_left -= 1
            hydra.queue(response.request)
          end
        end
      end
    end
  end
end
