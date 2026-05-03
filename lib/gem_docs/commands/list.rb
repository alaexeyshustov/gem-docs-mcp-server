# frozen_string_literal: true

module GemDocs
  module Commands
    class List < Base
      desc "Show installed gems"

      def call(format: "text", **_kwargs)
        gems = installed_specs
          .reject { |spec| config.exclude_gems.include?(spec.name) }
          .sort_by(&:name)
          .map { |spec| gem_payload(spec) }

        out.puts GemDocs::Formatters.for(format).list(gems: gems)
        0
      end

      private

      def installed_specs
        Gem::Specification.to_a
      end

      def doc_registry
        @doc_registry ||= GemDocs::DocRegistry.new
      end

      def gem_payload(spec)
        loaded_gem = doc_registry.load_gem(spec.name)

        {
          name: spec.name,
          version: spec.version.to_s,
          doc_source: loaded_gem.doc_source,
          summary: spec.summary
        }
      rescue StandardError
        {
          name: spec.name,
          version: spec.version.to_s,
          doc_source: :none,
          summary: spec.summary
        }
      end
    end
  end
end
