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
        payload = entries.map do |entry|
          normalized_entry = normalize_entry(entry)
          name = normalized_entry[:path] || normalized_entry.fetch(:name)
          type = normalized_entry.key?(:type) ? normalized_entry[:type] : normalized_entry.fetch(:kind).to_s
          summary = normalized_entry.key?(:summary) ? normalized_entry[:summary] : normalized_entry[:docstring].to_s
          payload_entry = {
            name: name,
            type: type,
            summary: summary,
            method_count: normalized_entry.fetch(:method_count, 0)
          }
          payload_entry[:superclass] = normalized_entry[:superclass] if normalized_entry[:superclass]
          payload_entry
        end

        call(payload)
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
