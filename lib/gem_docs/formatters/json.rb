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
        call(gems.map { |gem| compact_entry(gem) })
      end

      def summary(gem:)
        call(compact_entry(gem))
      end

      def classes(gem:, entries:)
        call(
          compact_value(
            gem: gem,
            classes: entries.map { |entry| compact_entry(entry) }
          )
        )
      end

      def lookup(result:)
        call(compact_entry(result))
      end

      def search(results:)
        call(results.map { |result| compact_entry(result) })
      end

      private

      def compact_entry(payload)
        compact_value(payload.transform_values { |value| value.is_a?(Symbol) ? value.to_s : value })
      end
    end
  end
end
