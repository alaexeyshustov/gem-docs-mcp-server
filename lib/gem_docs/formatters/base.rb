# frozen_string_literal: true

module GemDocs
  module Formatters
    class Base
      private

      def normalize_gem(gem)
        return compact_hash(gem) if gem.is_a?(Hash)

        case gem
        when GemDocs::DocRegistry::LoadedGem
          compact_hash(
            name: gem.name,
            version: gem.version,
            summary: gem.summary,
            description: gem.description,
            homepage: gem.homepage,
            license: gem.license,
            path: gem.path,
            doc_source: gem.doc_source,
            classes: gem.classes.map(&:path),
            entry_points: gem.entry_points
          )
        else
          compact_hash(gem.to_h)
        end
      end

      def normalize_entry(entry)
        return compact_hash(entry) if entry.is_a?(Hash)

        compact_hash(entry.to_h)
      end

      def compact_value(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), compacted|
            normalized = compact_value(nested_value)
            next if normalized.nil?
            next if normalized.respond_to?(:empty?) && normalized.empty?

            compacted[key] = normalized
          end
        when Array
          value.filter_map do |nested_value|
            normalized = compact_value(nested_value)
            normalized unless normalized.respond_to?(:empty?) && normalized.empty?
          end
        else
          value.is_a?(Symbol) ? value.to_s : value
        end
      end

      def compact_hash(hash)
        hash.each_with_object({}) do |(key, value), compacted|
          compacted[key.to_sym] = value
        end
      end
    end
  end
end
