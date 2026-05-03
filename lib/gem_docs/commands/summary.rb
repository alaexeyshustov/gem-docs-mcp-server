# frozen_string_literal: true

module GemDocs
  module Commands
    class Summary < Base
      desc "Summarize a gem"
      argument :gem_name, type: :string
      option :version, desc: "Gem version"

      def call(gem_name:, version: nil, format: "text", **_kwargs)
        out.puts GemDocs::Formatters.for(format).summary(gem: summary_payload(doc_registry.load_gem(gem_name, version: version)))
        0
      end

      private

      def doc_registry
        @doc_registry ||= GemDocs::DocRegistry.new
      end

      def summary_payload(loaded_gem)
        {
          name: loaded_gem.name,
          version: loaded_gem.version,
          description: loaded_gem.description.to_s.empty? ? loaded_gem.summary : loaded_gem.description,
          homepage: loaded_gem.homepage,
          license: loaded_gem.license,
          doc_source: loaded_gem.doc_source,
          classes: loaded_gem.classes.sort_by(&:path).map(&:path),
          entry_points: loaded_gem.entry_points
        }
      end
    end
  end
end
