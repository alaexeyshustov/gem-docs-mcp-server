# frozen_string_literal: true

module GemDocs
  module Formatters
    class Text < Base
      def call(payload)
        payload.to_s
      end

      def error(payload)
        payload.fetch(:message)
      end

      def list(gems:)
        rows = gems.map do |gem|
          [
            gem.fetch(:name),
            gem.fetch(:version),
            gem.fetch(:doc_source).to_s
          ]
        end
        widths = column_widths([ %w[NAME VERSION DOC\ SOURCE], *rows ])

        lines = [ format_row([ "NAME", "VERSION", "DOC SOURCE" ], widths) + "  SUMMARY" ]
        gems.each do |gem|
          summary = gem[:summary].to_s
          line = format_row(
            [
              gem.fetch(:name),
              gem.fetch(:version),
              gem.fetch(:doc_source).to_s
            ],
            widths
          )
          lines << [ line, summary ].reject(&:empty?).join("  ")
        end

        lines.join("\n") + "\n"
      end

      def summary(gem:)
        normalized_gem = normalize_gem(gem)
        entry_points = Array(normalized_gem[:entry_points])

        build_sections(
          "#{normalized_gem.fetch(:name)} #{normalized_gem.fetch(:version)} [#{normalized_gem.fetch(:doc_source)}]",
          normalized_gem[:description] || normalized_gem[:summary],
          normalized_gem[:homepage],
          normalized_gem[:license] ? "License: #{normalized_gem[:license]}" : nil,
          section("Classes", normalized_gem[:classes]),
          entry_points.empty? ? "Entry points: none documented" : build_sections("Entry points:", *entry_points.map { |entry| "  #{entry}" })
        )
      end

      def classes(entries:)
        normalized_entries = entries.map do |entry|
          normalized_entry = normalize_entry(entry)
          name = normalized_entry[:path] || normalized_entry.fetch(:name)
          type = normalized_entry.key?(:type) ? normalized_entry[:type] : normalized_entry.fetch(:kind).to_s
          summary = normalized_entry.key?(:summary) ? normalized_entry[:summary] : normalized_entry[:docstring].to_s
          {
            name: name,
            type: type,
            summary: summary,
            method_count: normalized_entry.fetch(:method_count, 0)
          }
        end

        widths = column_widths(
          normalized_entries.map do |entry|
            [
              entry.fetch(:name),
              entry.fetch(:type),
              method_count_label(entry.fetch(:method_count))
            ]
          end
        )

        normalized_entries.map do |entry|
          line = format_row(
            [
              entry.fetch(:name),
              entry.fetch(:type),
              method_count_label(entry.fetch(:method_count))
            ],
            widths
          )
          [ line, entry.fetch(:summary) ].reject(&:empty?).join("  ")
        end.join("\n")
      end

      def lookup(result:)
        normalized_result = normalize_entry(result)

        build_sections(
          normalized_result.fetch(:path),
          normalized_result[:signature],
          normalized_result[:docstring],
          source_location_line(normalized_result[:source_location])
        )
      end

      def search(results:)
        build_sections(*results.map { |result| "- #{normalize_entry(result).fetch(:path)}" })
      end

      private

      def build_sections(*lines)
        lines.compact.reject(&:empty?).join("\n")
      end

      def column_widths(rows)
        rows.transpose.map { |column| column.map(&:length).max }
      end

      def format_row(values, widths)
        values.each_with_index.map do |value, index|
          value.ljust(widths[index])
        end.join("  ")
      end

      def section(title, values)
        return if values.nil? || values.empty?

        "#{title}: #{values.join(', ')}"
      end

      def source_location_line(source_location)
        return if source_location.nil? || source_location.empty?

        "Source: #{source_location}"
      end

      def method_count_label(method_count)
        noun = method_count == 1 ? "method" : "methods"
        "(#{method_count} #{noun})"
      end
    end
  end
end
