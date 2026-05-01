# frozen_string_literal: true

require "dry/cli"

module GemDocs
  module Commands
    class Base < Dry::CLI::Command
      def placeholder(command_name)
        out.puts "#{command_name} is not implemented yet."
        exit(0)
      end
    end
  end
end
