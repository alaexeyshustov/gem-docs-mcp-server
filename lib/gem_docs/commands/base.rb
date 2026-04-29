# frozen_string_literal: true

module GemDocs
  module Commands
    class Base
      attr_reader :out, :err

      def initialize(out:, err:)
        @out = out
        @err = err
      end

      def placeholder(command_name)
        out.puts "#{command_name} is not implemented yet."
        0
      end
    end
  end
end
