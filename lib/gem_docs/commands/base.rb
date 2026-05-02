# frozen_string_literal: true

require "dry/cli"

module GemDocs
  module Commands
    class Base < Dry::CLI::Command
      option :format,
             values: %w[text json],
             default: "text",
             desc: "Output format"

      def placeholder(command_name)
        out.puts "#{command_name} is not implemented yet."
        0
      end

      def render_command_error(error, format: "text")
        err.puts(formatted_error(error, format: format))
        1
      end

      private

      def config
        GemDocs.config(root: Dir.pwd)
      end

      def formatted_error(error, format:)
        GemDocs::Formatters.for(format).error(error.to_h)
      end
    end
  end
end
