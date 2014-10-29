require 'service/client/caching/cache_entry'
require 'dalli'

if defined?(Rails)
  require 'service/caching/log_subscriber'
  require 'service/caching/railtie'
end

module Service::Client
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

    def cache_request(url, strategy: :last_resort, expires_in: 30.seconds, **options, &block)
      case strategy
      when :first_resort
        cache_first_resort(url, expires_in: expires_in, **options, &block)
      when :last_resort
        cache_last_resort(url, expires_in: expires_in, **options, &block)
      else
        no_cache(url, &block)
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
      begin
        response = block.call(url)

        entry = CacheEntry.new(cache_client, url, policy_group, response)

        # Only store a new result if we roll a 0
        r = rand(refresh_probability)
        entry.store(expires_in, refresh_window: 1.minute) if r == 0

        response
      rescue Service::ServiceError => ex
        cache_logger.error "Service responded with exception: #{ex.class.name}: #{ex.message}\n#{ex.backtrace.join('\n')}" if cache_logger

        entry = CacheEntry.fetch(cache_client, url, policy_group)
        if entry.nil?
          # Re-raise the error, no cached response
          raise ex
        end

        entry.touch(expires_in, refresh_window: 1.minute)
        entry.data
      end
    end

    ##
    # Use the cache as a first resort.  This path will only make a request if there is no entry in the cache
    # or if the cache entry has expired.  It follows logic similar to ActiveSupport::Cache.  If the cache entry
    # has expired (but is still present) and the request fails, the cached value is still returned, as if this was
    # cache_last_resort.
    def cache_first_resort(url, policy_group: 'general', expires_in: nil, &block)
      entry = CacheEntry.fetch(cache_client, url, policy_group)

      if entry
        if entry.expired?
          # Cache entry exists but is expired.  This call to cache_first_resort will refresh the cache by
          # calling the block, but to prevent lots of others from also trying to refresh, first it updates
          # the expiry date on the entry so that other callers that come in while we're requesting the update
          # don't also try to update the cache.
          entry.touch(expires_in)
        else
          return entry.data
        end
      end

      begin
        response = block.call(url)

        entry = CacheEntry.new(cache_client, url, policy_group, response)
        entry.store(expires_in)
        response
      rescue Service::ServiceError => ex
        cache_logger.error "Service responded with exception: #{ex.class.name}: #{ex.message}\n#{ex.backtrace.join('\n')}" if cache_logger

        if entry.nil?
          # Re-raise the error, no cached response
          raise ex
        end

        # Set the entry to be expired again (but reset the refresh window).  This allows the next call to try again
        # (assuming the circuit breaker is reset) but keeps the value in the cache in the meantime
        entry.touch(0.seconds)
        entry.data
      end
    end

    def no_cache(url, &block)
      block.call(url)
    end
  end
end
