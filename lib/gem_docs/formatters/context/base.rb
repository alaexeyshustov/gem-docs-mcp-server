# frozen_string_literal: true

module GemDocs
  module Formatters
    module Context
      class Base < GemDocs::Formatters::Base
        MAX_SUMMARY_LENGTH = 140
        MAX_CLASSES = 6
        MAX_ENTRY_POINTS = 3
        MAX_LIST_ITEM_LENGTH = 48

        private

        def documented_gems(gems)
          gems.filter_map do |gem|
            normalized_gem = normalize_gem(gem)
            normalized = compact_value(
              name: normalized_gem[:name],
              version: normalized_gem[:version],
              summary: normalized_gem[:summary],
              doc_source: normalized_gem[:doc_source],
              classes: normalized_gem[:classes],
              entry_points: normalized_gem[:entry_points]
            )

            normalized unless normalized[:doc_source] == "none"
          end
        end

        def gem_sections(gems)
          documented_gems(gems).map do |gem|
            lines = [ "## #{gem[:name]} (#{gem[:version]})" ]
            lines << "- Summary: #{truncate(gem[:summary], MAX_SUMMARY_LENGTH)}" if gem[:summary]
            lines << "- Documentation: #{gem[:doc_source]}"
            lines << "- Classes: #{format_list(gem[:classes], limit: MAX_CLASSES)}" if gem[:classes]
            lines << "- Entry points: #{format_list(gem[:entry_points], limit: MAX_ENTRY_POINTS)}" if gem[:entry_points]
            lines.join("\n")
          end
        end

        def format_list(values, limit:)
          items = Array(values).take(limit).map { |value| truncate(value, MAX_LIST_ITEM_LENGTH) }
          overflow = Array(values).length - items.length
          items << "... (+#{overflow} more)" if overflow.positive?
          items.join(", ")
        end

        def truncate(value, limit)
          text = value.to_s.strip
          return text if text.length <= limit

          "#{text[0, limit - 1]}…"
        end
      end
    end
  end
end
