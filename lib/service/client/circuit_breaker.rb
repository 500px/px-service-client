require 'circuit_breaker'
require 'singleton'

module Service::Client
  module CircuitBreaker
    extend ActiveSupport::Concern

    included do
      include ::CircuitBreaker
      include Singleton

      # Default circuit breaker configuration.  Can be overridden
      circuit_handler do |handler|
        handler.failure_threshold = 5
        handler.failure_timeout = 7
        handler.invocation_timeout = 5
        handler.excluded_exceptions = [Service::ServiceRequestError]
      end

      class <<self
        alias_method_chain :circuit_method, :exceptions
      end
    end


    module ClassMethods
      ##
      # Takes a splat of method names, and wraps them with the circuit_handler.
      # Overrides the circuit_method provided by ::CircuitBreaker
      def circuit_method_with_exceptions(*methods)
        circuit_handler = self.circuit_handler

        methods.each do |meth|
          m = instance_method(meth)
          define_method(meth) do |*args|
            begin
              circuit_handler.handle(self.circuit_state, m.bind(self), *args)
            rescue Service::ServiceError, Service::ServiceRequestError => ex
              raise ex
            rescue StandardError => ex
              # Wrap other exceptions, includes CircuitBreaker::CircuitBrokenException
              raise Service::ServiceError.new(ex.message, 503), ex, ex.backtrace
            end
          end
        end
      end
    end
  end
end
