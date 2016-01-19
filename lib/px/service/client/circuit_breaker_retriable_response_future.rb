module Px::Service::Client
  class CircuitBreakerRetriableResponseFuture < RetriableResponseFuture

    ##
    # Sets the value of a RetriableResponseFuture to the exception
    # raised when opening the circuit breaker.
    def initialize(ex)
      super()
      
      complete(ex)
    end
  end
end