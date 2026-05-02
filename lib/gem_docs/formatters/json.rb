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
        call(compact_value(normalize_gem(gem)))
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
