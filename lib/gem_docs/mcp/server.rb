# frozen_string_literal: true

module GemDocs
  module MCP
    class Server
      def self.start(_arguments = [], out: $stdout, err: $stderr)
        return 1 unless load_fast_mcp(err)

        out.puts "gem-docs-server placeholder loaded"
        0
      end

      def self.load_fast_mcp(err)
        require "fast_mcp"
        true
      rescue LoadError
        err.puts "gem-docs-server requires the optional fast-mcp gem."
        false
      rescue StandardError => e
        err.puts "gem-docs-server failed to load fast-mcp: #{e.class}: #{e.message}"
        false
      end

      private_class_method :load_fast_mcp
    end
  end
end
