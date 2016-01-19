module Px::Service::Client::Caching
  class CacheEntry
    attr_accessor :url, :data, :expires_at, :policy_group
    attr_reader :cache_client

    def initialize(cache_client, url, policy_group, data, expires_at = nil)
      @cache_client = cache_client
      self.url = url
      self.data = data
      self.expires_at = expires_at
      self.policy_group = policy_group
    end

    def expired?
      expires_at < DateTime.now
    end

    ##
    # Store this entry in the cache with the given expiry.
    def store(expires_in, refresh_window: 5.minutes)
      raise ArgumentError.new('Cache client has not been set.') unless cache_client.present?

      self.expires_at = DateTime.now + expires_in

      ActiveSupport::Notifications.instrument("store.caching", { url: url, policy_group: policy_group, expires_in: expires_in} ) do
        real_expiry = real_cache_expiry(expires_in, refresh_window: refresh_window)
        cache_client.multi do
          data_json = data.is_a?(Hash) ? data.to_json : data
          cache_client.set(cache_key(:data), data_json, real_expiry)
          cache_client.set(cache_key(:meta), metadata, real_expiry)
        end
      end
    end

    ##
    # Fetch an entry from the cache.  Returns the entry if it's present, otherwise returns nil
    def self.fetch(cache_client, url, policy_group)
      raise ArgumentError.new('Cache client has not been set.') unless cache_client.present?

      key_values = nil
      data_key = cache_key(url, policy_group, :data)
      meta_key = cache_key(url, policy_group, :meta)
      ActiveSupport::Notifications.instrument("get.caching", { url: url, policy_group: policy_group } ) do
        key_values = cache_client.get_multi(data_key, meta_key)
      end

      data_json = key_values[data_key]
      meta_json = key_values[meta_key]
      if data_json && meta_json
        data = JSON.parse(data_json)
        meta = JSON.parse(meta_json)
        CacheEntry.new(cache_client, meta['url'], meta['pg'], data, meta['expires_at'])
      else
        nil
      end
    end

    ##
    # Touch this entry in the cache, updating its expiry time but not its data
    def touch(expires_in, refresh_window: 5.minutes)
      raise ArgumentError.new('Cache client has not been set.') unless cache_client.present?

      self.expires_at = DateTime.now + expires_in

      ActiveSupport::Notifications.instrument("touch.caching", { url: url, policy_group: policy_group, expires_in: expires_in} ) do
        real_expiry = real_cache_expiry(expires_in, refresh_window: refresh_window)

        cache_client.touch(cache_key(:data), real_expiry)
        cache_client.set(cache_key(:meta), metadata, real_expiry)
      end
    end

    private

    def metadata
      {
        "url" => url,
        "pg" => policy_group,
        "expires_at" => expires_at,
      }.to_json
    end

    def cache_key(type)
      self.class.cache_key(url, policy_group, type)
    end

    def self.cache_key(url, policy_group, type)
      "#{policy_group}_#{cache_key_base(url)}_#{type}"
    end

    ##
    # Get the cache key for the given query string
    def self.cache_key_base(url)
      md5 = Digest::MD5.hexdigest(url.to_s)
      "#{self.class.name.parameterize}_#{md5}"
    end

    def real_cache_expiry(expires_in, refresh_window: nil)
      (expires_in + refresh_window).to_i
    end
  end
end
