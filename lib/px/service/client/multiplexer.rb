module Px::Service::Client
  class Multiplexer
    attr_accessor :hydra
    attr_accessor :states

    def initialize(params = {})
      self.hydra = Typhoeus::Hydra.new(params)
    end

    def context
      Fiber.new{ yield }.resume
      self
    end

    ##
    # Queue a request on the multiplexer, with retry
    def do(request_or_future, retries: RetriableResponseFuture::DEFAULT_RETRIES)
      response = request_or_future
      if request_or_future.is_a?(Typhoeus::Request)
        response = RetriableResponseFuture.new(request_or_future, retries: retries)
      elsif !request_or_future.is_a?(RetriableResponseFuture) || request_or_future.completed?
        return request_or_future
      end

      # Will automatically queue the request on the hydra
      response.hydra = hydra
      response
    end

    ##
    # Start the multiplexer.
    def run
      hydra.run
    end
  end
end
