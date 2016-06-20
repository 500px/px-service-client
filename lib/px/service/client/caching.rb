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

      config do |config|
        config.cache_strategy = :none
        config.cache_expiry = 30.seconds
        config.cache_max_page = nil
        config.cache_options = {
          policy_group: 'general',
        }
        config.cache_logger = nil
        config.cache_client = nil
      end

      # DEPRECATED: Use .config (base class method) instead
      alias_method :caching, :config
    end

    def cache_request(url, strategy: nil, policy_group: config.cache_options[:policy_group], expires_in: config.cache_expiry, refresh_probability: 1)
      case strategy
        when :last_resort
          cache_last_resort(url, policy_group: policy_group, expires_in: expires_in, refresh_probability: refresh_probability) { yield  }
        when :first_resort
          cache_first_resort(url, policy_group: policy_group, expires_in: expires_in) { yield }
        else
          no_cache { yield }
      end
    end

    private

    ##
    # Use the cache as a last resort.  This path will make the request each time, caching the result
    # on success.  If an exception occurs, the cache is checked for a result.  If the cache has a result, it's
    # returned and the cache entry is touched to prevent expiry.  Otherwise, the original exception is re-raised.
    def cache_last_resort(url, policy_group: 'general', expires_in: nil, refresh_probability: 1)
      tags = [
        "type:last_resort",
        "policy_group:#{policy_group}",
      ]

      # Note we use a smaller refresh window here (technically, could even use 0)
      # since we don't really need the "expired but not really expired" behaviour when caching as a last resort.
      retry_response = yield

      Future.new do
        begin
          raise ArgumentError.new('Block did not return a Future.') unless retry_response.is_a?(Future)
          resp = retry_response.value!
          entry = CacheEntry.new(config.cache_client, url, policy_group, resp)

          # Only store a new result if we roll a 0
          r = rand(refresh_probability)
          if r == 0
            entry.store(expires_in, refresh_window: 1.minute)
            config.statsd_client.increment("caching.write.count", tags: tags)
          end
          resp
        rescue Px::Service::ServiceError => ex
          config.cache_logger.error "Service responded with exception: #{ex.class.name}: #{ex.message}\n#{ex.backtrace.join('\n')}" if config.cache_logger
          entry = CacheEntry.fetch(config.cache_client, url, policy_group)
          if entry.nil?
            # Re-raise the error, no cached response
            config.statsd_client.increment("caching.fetch.count", tags: tags + ["result:miss"])
            raise ex
          end

          config.statsd_client.increment("caching.fetch.count", tags: tags + ["result:hit"])
          entry.touch(expires_in, refresh_window: 1.minute)
          entry.data
        end
      end
    end

    ##
    # Use the cache as a first resort.  This path will only make a request if there is no entry in the cache
    # or if the cache entry has expired.  It follows logic similar to ActiveSupport::Cache.  If the cache entry
    # has expired (but is still present) and the request fails, the cached value is still returned, as if this was
    # cache_last_resort.
    def cache_first_resort(url, policy_group: 'general', expires_in: nil)
      tags = [
        "type:last_resort",
        "policy_group:#{policy_group}",
      ]
      entry = CacheEntry.fetch(config.cache_client, url, policy_group)

      if entry
        if entry.expired?
          # Cache entry exists but is expired.  This call to cache_first_resort will refresh the cache by
          # calling the block, but to prevent lots of others from also trying to refresh, first it updates
          # the expiry date on the entry so that other callers that come in while we're requesting the update
          # don't also try to update the cache.
          config.statsd_client.increment("caching.fetch.count", tags: tags + ["result:expired"])
          entry.touch(expires_in)
        else
          config.statsd_client.increment("caching.fetch.count", tags: tags + ["result:hit"])
          return Future.new { entry.data }
        end
      end

      retry_response = yield

      Future.new do
        begin
          raise ArgumentError.new('Block did not return a Future.') unless retry_response.is_a?(Future)
          resp = retry_response.value!
          entry = CacheEntry.new(config.cache_client, url, policy_group, resp)
          entry.store(expires_in)
          config.statsd_client.increment("caching.write.count", tags: tags)
          resp
        rescue Px::Service::ServiceError => ex
          config.cache_logger.error "Service responded with exception: #{ex.class.name}: #{ex.message}\n#{ex.backtrace.join('\n')}" if config.cache_logger

          entry = CacheEntry.fetch(config.cache_client, url, policy_group)
          if entry.nil?
            # Re-raise the error, no cached response
            # config.statsd_client.increment("caching.fetch.count", tags: tags + ["result:miss"])
            raise ex
          end
          config.statsd_client.increment("caching.fetch.count", tags: tags + ["result:hit"])

          # Set the entry to be expired again (but reset the refresh window).  This allows the next call to try again
          # (assuming the circuit breaker is reset) but keeps the value in the cache in the meantime
          entry.touch(0.seconds)
          entry.data
        end
      end

    rescue ArgumentError => ex
      Future.new { ex }
    end

    def no_cache
      retry_response = yield

      Future.new do
        raise ArgumentError.new('Block did not return a Future.') unless retry_response.is_a?(Future)

        retry_response.value!
      end
    end
  end
end
