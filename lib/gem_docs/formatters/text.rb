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
        metadata = [
          [ normalized_result[:gem], normalized_result[:version] ].compact.join(" "),
          normalized_result[:doc_source]
        ].reject { |value| value.nil? || value.to_s.empty? }.join(" · ")

        build_sections(
          metadata.empty? ? normalized_result.fetch(:path) : "#{normalized_result.fetch(:path)}  [#{metadata}]",
          normalized_result[:source_location],
          nil,
          normalized_result[:signature],
          normalized_result[:docstring],
          tag_sections(normalized_result[:tags]),
          aliases_section(normalized_result[:aliases])
        )
      end

      def search(results:)
        normalized_results = results.map do |result|
          normalized_result = normalize_entry(result)
          {
            path: normalized_result.fetch(:path),
            gem: normalized_result[:gem].to_s,
            score: format("%.2f", normalized_result.fetch(:score, 0).to_f),
            summary: normalized_result.fetch(:summary, normalized_result[:docstring].to_s).to_s
          }
        end
        return "" if normalized_results.empty?

        widths = column_widths(
          normalized_results.map do |result|
            [ result.fetch(:path), result.fetch(:gem), result.fetch(:score) ]
          end
        )

        normalized_results.map do |result|
          line = format_row(
            [ result.fetch(:path), result.fetch(:gem), result.fetch(:score) ],
            widths
          ).rstrip
          [ line, result.fetch(:summary) ].reject(&:empty?).join("  ")
        end.join("\n")
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

      def tag_sections(tags)
        return "" unless tags.is_a?(Hash)

        tags.flat_map do |tag_name, values|
          case tag_name.to_s
          when "param"
            build_param_lines(values)
          when "return"
            build_type_lines("Returns", values)
          when "raise"
            build_type_lines("Raises", values)
          when "example"
            build_example_lines(values)
          else
            next
          end
        end.compact.join("\n")
      end

      def build_param_lines(values)
        return unless values.is_a?(Array) && !values.empty?

        [
          "Params:",
          *values.map do |value|
            next value.to_s unless value.is_a?(Hash)

            types = Array(value[:types]).join(" | ")
            [ "  #{value[:name]}", types, value[:text] ].reject(&:empty?).join("  ")
          end
        ].compact
      end

      def build_type_lines(title, values)
        return unless values.is_a?(Array)

        value = values.first
        return unless value.is_a?(Hash)

        raw_types = value.fetch(:types, nil)
        types = raw_types.is_a?(Array) ? raw_types.map { |type| type.to_s }.join(" | ") : ""
        [ title + ":", types, value.fetch(:text, "").to_s ].reject(&:empty?).join("  ")
      end

      def build_example_lines(values)
        return unless values.is_a?(Array) && !values.empty?

        [
          "Example:",
          *values.map { |value| "  #{value}" }
        ]
      end

      def aliases_section(aliases)
        aliases = Array(aliases)
        return if aliases.empty?

        "Aliases: #{aliases.join(', ')}"
      end

      def method_count_label(method_count)
        noun = method_count == 1 ? "method" : "methods"
        "(#{method_count} #{noun})"
      end
    end
  end
end
