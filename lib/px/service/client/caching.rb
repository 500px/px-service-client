require 'px/service/client/caching/cache_entry'
require 'dalli'

if defined?(Rails)
  require 'px/service/client/caching/log_subscriber'
  require 'px/service/client/caching/railtie'
end

module Px::Service::Client
  module Caching
    extend ActiveSupport::Concern

    STRATEGIES = [
      NO_CACHE = :none,
      LAST_RESORT = :last_resort,
      FIRST_RESORT = :first_resort,
    ]

    included do
      cattr_accessor :cache_client, :cache_logger
    end

    module ClassMethods
      DefaultConfig = Struct.new(:cache_strategy, :cache_expiry, :max_page, :cache_options, :cache_logger, :cache_client) do
        def initialize
          self.cache_strategy = :none
          self.cache_expiry = 30.seconds
          self.max_page = nil
          self.cache_options = {}
          self.cache_options[:policy_group] = 'general'
          self.cache_logger = nil
          self.cache_client = nil
        end
      end

      ##
      # Set the caching behaviour
      def caching(&block)
        @cache_config ||= DefaultConfig.new
        yield(@cache_config) if block_given?
        @cache_config
      end
    end
    
    def config
      @cache_config || self.class.caching
    end

    def cache_request(url, strategy: nil, **options, &block)
      strategy ||= config.cache_strategy

      case strategy
      when :first_resort
        cache_first_resort(url, policy_group: config.cache_options[:policy_group], expires_in: config.cache_expiry, **options, &block)
      when :last_resort
        cache_last_resort(url, policy_group: config.cache_options[:policy_group], expires_in: config.cache_expiry, **options, &block)
      else
        no_cache(&block)
      end
    end

    private

    ##
    # Use the cache as a last resort.  This path will make the request each time, caching the result
    # on success.  If an exception occurs, the cache is checked for a result.  If the cache has a result, it's
    # returned and the cache entry is touched to prevent expiry.  Otherwise, the original exception is re-raised.
    def cache_last_resort(url, policy_group: 'general', expires_in: nil, refresh_probability: 1, &block)
      # Note we use a smaller refresh window here (technically, could even use 0)
      # since we don't really need the "expired but not really expired" behaviour when caching as a last resort.
      retry_response = block.call

      Future.new do
        begin
          raise ArgumentError.new('Block did not return a Future.') unless retry_response.is_a?(Future)
          resp = retry_response.value!

          entry = CacheEntry.new(config.cache_client, url, policy_group, resp.options)

          # Only store a new result if we roll a 0
          r = rand(refresh_probability)
          entry.store(expires_in, refresh_window: 1.minute) if r == 0
          resp
        rescue Px::Service::ServiceError => ex
          cache_logger.error "Service responded with exception: #{ex.class.name}: #{ex.message}\n#{ex.backtrace.join('\n')}" if cache_logger

          entry = CacheEntry.fetch(config.cache_client, url, policy_group)
          if entry.nil?
            # Re-raise the error, no cached response
            raise ex
          end

          entry.touch(expires_in, refresh_window: 1.minute)
          Typhoeus::Response.new(HashWithIndifferentAccess.new(entry.data))
        end
      end
    end

    ##
    # Use the cache as a first resort.  This path will only make a request if there is no entry in the cache
    # or if the cache entry has expired.  It follows logic similar to ActiveSupport::Cache.  If the cache entry
    # has expired (but is still present) and the request fails, the cached value is still returned, as if this was
    # cache_last_resort.
    def cache_first_resort(url, policy_group: 'general', expires_in: nil, &block)
      entry = CacheEntry.fetch(config.cache_client, url, policy_group)

      if entry
        if entry.expired?
          # Cache entry exists but is expired.  This call to cache_first_resort will refresh the cache by
          # calling the block, but to prevent lots of others from also trying to refresh, first it updates
          # the expiry date on the entry so that other callers that come in while we're requesting the update
          # don't also try to update the cache.
          entry.touch(expires_in)
        else
          return Future.new { Typhoeus::Response.new(HashWithIndifferentAccess.new(entry.data)) }
        end
      end

      retry_response = block.call

      Future.new do
        begin
          raise ArgumentError.new('Block did not return a Future.') unless retry_response.is_a?(Future)
          resp = retry_response.value!
          
          entry = CacheEntry.new(config.cache_client, url, policy_group, resp.options)
          entry.store(expires_in)
          resp
        rescue Px::Service::ServiceError => ex
          cache_logger.error "Service responded with exception: #{ex.class.name}: #{ex.message}\n#{ex.backtrace.join('\n')}" if cache_logger

          entry = CacheEntry.fetch(config.cache_client, url, policy_group)
          if entry.nil?
            # Re-raise the error, no cached response
            raise ex
          end

          # Set the entry to be expired again (but reset the refresh window).  This allows the next call to try again
          # (assuming the circuit breaker is reset) but keeps the value in the cache in the meantime
          entry.touch(0.seconds)
          Typhoeus::Response.new(HashWithIndifferentAccess.new(entry.data))
        end
      end
    end

    def no_cache(&block)
      retry_response = block.call

      Future.new do
        raise ArgumentError.new('Block did not return a Future.') unless retry_response.is_a?(Future)

        retry_response.value!
      end
    end
  end
end
