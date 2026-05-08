# frozen_string_literal: true

module GemDocs
  class CachingGemLoader
    def initialize(loader:, cache:, invalidation_key_provider:, loaded_gem_hydrator: nil)
      @loader = loader
      @cache = cache
      @invalidation_key_provider = invalidation_key_provider
      @loaded_gem_hydrator = loaded_gem_hydrator || ->(_spec, loaded_gem) { loaded_gem }
      # @type var invalidation_keys: Hash[[String, String], String]
      invalidation_keys = {}
      @invalidation_keys = invalidation_keys
    end

    def load(name, version: nil, spec: nil)
      loaded_gem, = load_with_invalidation_key(name, version: version, spec: spec)
      loaded_gem
    end

    def load_with_invalidation_key(name, version: nil, spec: nil)
      spec ||= resolve_spec!(name, version: version)
      invalidation_key = invalidation_key_for(spec)
      cached_gem = fetch_cached_loaded_gem(spec, invalidation_key: invalidation_key)
      return [ cached_gem, invalidation_key ] if cached_gem

      loaded_gem = @loader.load(name, version: version, spec: spec)
      persist_loaded_gem(loaded_gem, invalidation_key: invalidation_key)
      [ loaded_gem, invalidation_key ]
    end

    def detect_source(spec)
      invalidation_key = invalidation_key_for(spec)
      cached_gem = fetch_cached_loaded_gem(spec, invalidation_key: invalidation_key)
      return cached_gem.doc_source if cached_gem

      @loader.detect_source(spec)
    end

    def invalidation_key_for(spec)
      @invalidation_keys.fetch(invalidation_cache_key(spec)) do
        @invalidation_keys[invalidation_cache_key(spec)] = @invalidation_key_provider.call(spec)
      end
    rescue StandardError
      nil
    end

    def provider_available?(spec)
      @loader.provider_available?(spec)
    end

    def resolve_spec!(name, version: nil)
      @loader.resolve_spec!(name, version: version)
    end

    private

    def fetch_cached_loaded_gem(spec, invalidation_key:)
      return unless @cache && invalidation_key

      cached_gem = @cache.fetch_loaded_gem(
        gem_name: spec.name,
        gem_version: spec.version.to_s,
        invalidation_key: invalidation_key
      )
      return unless cached_gem

      @loaded_gem_hydrator.call(spec, cached_gem)
    rescue StandardError
      nil
    end

    def persist_loaded_gem(loaded_gem, invalidation_key:)
      return unless @cache && invalidation_key && loaded_gem

      @cache.write_loaded_gem(loaded_gem, invalidation_key: invalidation_key)
    rescue StandardError
      nil
    end

    def invalidation_cache_key(spec)
      [ spec.full_gem_path, spec.version.to_s ]
    end
  end
end
