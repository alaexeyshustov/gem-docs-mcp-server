# frozen_string_literal: true

module GemDocs
  class CachingGemLoader
    def initialize(
      loader:,
      cache:,
      invalidation_key_provider:,
      loaded_gem_hydrator: nil,
      source_artifact_builder: nil
    )
      @loader = loader
      @cache = cache
      @invalidation_key_provider = invalidation_key_provider
      @loaded_gem_hydrator = loaded_gem_hydrator || ->(_spec, loaded_gem) { loaded_gem }
      @source_artifact_builder = source_artifact_builder
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
      if cached_gem
        ensure_source_artifacts_persisted(cached_gem, invalidation_key: invalidation_key) if invalidation_key
        return [ cached_gem, invalidation_key ]
      end

      loaded_gem = @loader.load(name, version: version, spec: spec)
      persist_loaded_gem(loaded_gem, invalidation_key: invalidation_key)
      ensure_source_artifacts_persisted(loaded_gem, invalidation_key: invalidation_key) if loaded_gem && invalidation_key
      [ loaded_gem, invalidation_key ]
    end

    def detect_source(spec)
      invalidation_key = invalidation_key_for(spec)
      cached_gem = fetch_cached_loaded_gem(spec, invalidation_key: invalidation_key)
      return cached_gem.doc_source if cached_gem

      @loader.detect_source(spec)
    end

    def source_artifacts_for(name, version: nil, spec: nil)
      loaded_gem, invalidation_key = load_with_invalidation_key(name, version: version, spec: spec)
      return [] unless @cache && invalidation_key && loaded_gem

      ensure_source_artifacts_persisted(loaded_gem, invalidation_key: invalidation_key)
    end

    def lookup_artifact_for(path, gem_name:, version: nil, spec: nil)
      loaded_gem, invalidation_key = load_with_invalidation_key(gem_name, version: version, spec: spec)
      return unless @cache && invalidation_key && loaded_gem

      ensure_source_artifacts_persisted(loaded_gem, invalidation_key: invalidation_key)
      @cache.fetch_with_fallback(
        gem_name: loaded_gem.name,
        gem_version: loaded_gem.version,
        lookup_target: path,
        invalidation_key: invalidation_key
      )
    rescue StandardError
      nil
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

    def persist_source_artifacts(loaded_gem, invalidation_key:)
      return unless @source_artifact_builder

      loaded_gem.objects.dup.each do |entry|
        resolved_entry = loaded_gem.find(entry.path) || entry
        @cache.write_artifact(
          gem_name: loaded_gem.name,
          gem_version: loaded_gem.version,
          lookup_target: resolved_entry.path,
          artifact_kind: :source,
          payload: @source_artifact_builder.call(loaded_gem, resolved_entry),
          invalidation_key: invalidation_key
        )
      end
    end

    def ensure_source_artifacts_persisted(loaded_gem, invalidation_key:)
      return [] unless @source_artifact_builder

      artifacts = @cache.source_artifacts(
        gem_name: loaded_gem.name,
        gem_version: loaded_gem.version,
        invalidation_key: invalidation_key
      )
      return artifacts unless artifacts.empty? && !loaded_gem.objects.empty?

      persist_source_artifacts(loaded_gem, invalidation_key: invalidation_key)
      @cache.source_artifacts(
        gem_name: loaded_gem.name,
        gem_version: loaded_gem.version,
        invalidation_key: invalidation_key
      )
    rescue StandardError
      []
    end

    def invalidation_cache_key(spec)
      [ spec.full_gem_path, spec.version.to_s ]
    end
  end
end
