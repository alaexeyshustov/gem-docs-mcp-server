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
        build_sections(
          "#{gem.fetch(:name)} (#{gem.fetch(:version)})",
          gem[:summary],
          "Documentation: #{gem[:doc_source]}",
          section("Classes", gem[:classes]),
          section("Entry points", gem[:entry_points])
        )
      end

      def classes(gem:, entries:)
        build_sections(
          "#{gem} classes",
          *entries.map { |entry| "- #{entry.fetch(:path)}" }
        )
      end

      def lookup(result:)
        build_sections(
          result.fetch(:path),
          result[:signature],
          result[:docstring],
          "Source: #{result[:source_location]}"
        )
      end

      def search(results:)
        build_sections(*results.map { |result| "- #{result.fetch(:path)}" })
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
    end
  end
end
