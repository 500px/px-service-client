require 'circuit_breaker'

module Px::Service::Client
  module CircuitBreaker
    extend ActiveSupport::Concern
    include ::CircuitBreaker

    included do
      # Default circuit breaker configuration.  Can be overridden
      circuit_handler do |handler|
        handler.failure_threshold = 5
        handler.failure_timeout = 7
        handler.invocation_timeout = 5
        handler.excluded_exceptions = [Px::Service::ServiceRequestError]
      end

      cattr_accessor :circuit_state do
        ::CircuitBreaker::CircuitState.new
      end

      alias_method_chain :_make_request, :breaker
    end

    ##
    # Make the request, respecting the circuit breaker, if configured
    def _make_request_with_breaker(method, uri, query: nil, headers: nil, body: nil, timeout: nil, stats_tags: [])
      state = self.class.circuit_state
      handler = self.class.circuit_handler

      if handler.is_tripped(state)
        handler.logger.debug("handle: breaker is tripped, refusing to execute: #{state}") if handler.logger
        begin
          handler.on_circuit_open(state)
        rescue StandardError => ex
          # Wrap and reroute other exceptions, includes CircuitBreaker::CircuitBrokenException
          error = Px::Service::ServiceError.new(ex.message, 503)
          return CircuitBreakerRetriableResponseFuture.new(error)
        end
      end

      config.statsd_client.increment("breakers.ready.count", tags: stats_tags) if circuit_state.half_open?

      retry_request = _make_request_without_breaker(
        method,
        uri,
        query: query,
        headers: headers,
        body: body,
        timeout: handler.invocation_timeout,
        stats_tags: stats_tags)

      retry_request.request.on_complete do |response|
        # Wait for request to exhaust retries
        if retry_request.completed?
          if response.response_code >= 500 || response.response_code == 0
            config.statsd_client.increment("breakers.fail.count", tags: stats_tags)
            config.statsd_client.increment("breakers.tripped.count", tags: stats_tags) if circuit_state.closed?

            handler.on_failure(state)
          else
            config.statsd_client.increment("breakers.reset.count", tags: stats_tags) unless circuit_state.closed?
            handler.on_success(state)
          end
        end
      end

      retry_request
    end

  end
end
