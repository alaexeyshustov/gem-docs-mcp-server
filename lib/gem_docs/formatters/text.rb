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

      def classes(gem:, entries:)
        build_sections(
          "#{gem} classes",
          *entries.map { |entry| "- #{normalize_entry(entry).fetch(:path)}" }
        )
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
    end
  end
end
