# frozen_string_literal: true

module GemDocs
  class GemLoader
    def initialize(spec_resolver:, doc_source_detector:, source_loader:, loaded_gem_builder:, yard_provider: nil)
      @spec_resolver = spec_resolver
      @doc_source_detector = doc_source_detector
      @source_loader = source_loader
      @loaded_gem_builder = loaded_gem_builder
      @yard_provider = yard_provider
    end

    def load(name, version: nil, spec: nil)
      spec ||= resolve_spec!(name, version: version)
      doc_source = detect_source(spec)
      return @yard_provider.load(spec) if doc_source == :yard
      return unless doc_source == :source_only || doc_source == :none

      load_fallback(spec, doc_source: doc_source)
    end

    def detect_source(spec)
      return :yard if @yard_provider&.available?(spec)

      @doc_source_detector.call(spec)
    end

    def provider_available?(spec)
      !@yard_provider.nil? && @yard_provider.available?(spec)
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
