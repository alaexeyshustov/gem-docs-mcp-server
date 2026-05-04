# frozen_string_literal: true

require "json"
require "stringio"

module GemDocs
  module MCP
    class CommandTool < ::FastMcp::Tool
      class << self
        def command(command_class = nil)
          return @command_class if command_class.nil?

          @command_class = command_class
        end
      end

      def call(**kwargs)
        response = execute_command(**command_arguments(**kwargs))

        {
          content: [ { type: "text", text: response.fetch(:body) } ],
          isError: !response.fetch(:success)
        }
      end

      private

      def command_arguments(**kwargs)
        kwargs
      end

      def execute_command(**kwargs)
        stdout = StringIO.new
        stderr = StringIO.new
        command_class = self.class.command
        raise "MCP tool command class is not configured" if command_class.nil?

        command = command_class.new
        command.define_singleton_method(:out) { stdout }
        command.define_singleton_method(:err) { stderr }

        status = begin
          command.call(**kwargs, format: "json")
        rescue GemDocs::Error => e
          command.render_command_error(e, format: "json")
        rescue StandardError => e
          stderr.puts(JSON.generate(error: "internal_error", message: e.message))
          1
        end

        {
          success: status.zero?,
          body: status.zero? ? stdout.string : stderr.string
        }
      end
    end
  end
end
