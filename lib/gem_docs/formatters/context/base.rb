# frozen_string_literal: true

module GemDocs
  module Formatters
    module Context
      class Base < GemDocs::Formatters::Base
        private

        def documented_gems(gems)
          gems.filter_map do |gem|
            normalized = compact_value(
              name: gem[:name],
              version: gem[:version],
              summary: gem[:summary],
              doc_source: gem[:doc_source]&.to_s,
              classes: gem[:classes],
              entry_points: gem[:entry_points]
            )

            normalized unless normalized[:doc_source] == "none"
          end
        end

        def gem_sections(gems)
          documented_gems(gems).map do |gem|
            lines = [ "## #{gem[:name]} (#{gem[:version]})" ]
            lines << "- Summary: #{gem[:summary]}" if gem[:summary]
            lines << "- Documentation: #{gem[:doc_source]}"
            lines << "- Classes: #{gem[:classes].join(', ')}" if gem[:classes]
            lines << "- Entry points: #{gem[:entry_points].join(', ')}" if gem[:entry_points]
            lines.join("\n")
          end
        end
      end
    end
  end
end
