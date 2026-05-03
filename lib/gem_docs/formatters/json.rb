# frozen_string_literal: true

require "json"

module GemDocs
  module Formatters
    class Json < Base
      def call(payload)
        JSON.pretty_generate(payload)
      end

      def error(payload)
        call(compact_value(payload))
      end

      def list(gems:)
        call(gems.map { |gem| compact_value(normalize_gem(gem)) })
      end

      def summary(gem:)
        normalized_gem = normalize_gem(gem)
        payload = {
          name: normalized_gem.fetch(:name),
          version: normalized_gem.fetch(:version),
          doc_source: normalized_gem.fetch(:doc_source).to_s,
          classes: Array(normalized_gem[:classes]),
          entry_points: Array(normalized_gem[:entry_points])
        }
        description = normalized_gem[:description] || normalized_gem[:summary]
        payload[:description] = description if description && !description.empty?
        payload[:homepage] = normalized_gem[:homepage] if normalized_gem[:homepage] && !normalized_gem[:homepage].empty?
        payload[:license] = normalized_gem[:license] if normalized_gem[:license] && !normalized_gem[:license].empty?

        call(payload)
      end

      def classes(gem:, entries:)
        call(
          compact_value(
            gem: gem,
            classes: entries.map { |entry| compact_value(normalize_entry(entry)) }
          )
        )
      end

      def lookup(result:)
        call(compact_value(normalize_entry(result)))
      end

      def search(results:)
        call(results.map { |result| compact_value(normalize_entry(result)) })
      end
    end
  end
end
