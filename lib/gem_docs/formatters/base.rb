# frozen_string_literal: true

module GemDocs
  module Formatters
    class Base
      private

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
          value
        end
      end
    end
  end
end
