# frozen_string_literal: true

module GemDocs
  class GemLoader
    def initialize(
      spec_resolver:,
      doc_source_detector:,
      source_loader:,
      loaded_gem_builder:,
      yard_provider: nil,
      rdoc_provider: nil
    )
      @spec_resolver = spec_resolver
      @doc_source_detector = doc_source_detector
      @source_loader = source_loader
      @loaded_gem_builder = loaded_gem_builder
      @yard_provider = yard_provider
      @rdoc_provider = rdoc_provider
    end

    def load(name, version: nil, spec: nil)
      spec ||= resolve_spec!(name, version: version)
      doc_source = detect_source(spec)
      return @yard_provider.load(spec) if doc_source == :yard && @yard_provider
      return @rdoc_provider.load(spec) if doc_source == :rdoc && @rdoc_provider
      return load_fallback(spec) if [ :yard, :rdoc ].include?(doc_source)
      return unless doc_source == :source_only || doc_source == :none

      load_fallback(spec, doc_source: doc_source)
    end

    def detect_source(name_or_spec, version: nil, spec: nil)
      spec ||= name_or_spec.is_a?(String) ? resolve_spec!(name_or_spec, version: version) : name_or_spec
      return :yard if @yard_provider&.available?(spec)
      return :rdoc if @rdoc_provider&.available?(spec)

      @doc_source_detector.call(spec)
    end

    def invalidation_key_for(_name, version: nil, spec: nil)
      nil
    end

    def source_artifacts_for(_name, version: nil, spec: nil)
      []
    end

    def lookup_artifact_for(_path, gem_name:, version: nil, spec: nil)
      nil
    end

    def provider_available?(spec)
      @yard_provider&.available?(spec) || @rdoc_provider&.available?(spec) || false
    end

    def load_fallback(spec, doc_source: nil)
      # @type var objects: Array[GemDocs::DocRegistry::Entry]
      objects = @source_loader.call(spec)
      resolved_doc_source = doc_source || (objects.empty? ? :none : :source_only)
      @loaded_gem_builder.call(spec, objects, resolved_doc_source)
    end

    def resolve_spec!(name, version: nil)
      spec = if version.nil? || version.empty?
        @spec_resolver.call(name)
      else
        @spec_resolver.call(name, version: version)
      end
      return spec if spec

      raise GemDocs::GemNotFound.new(name)
    end
  end
end
