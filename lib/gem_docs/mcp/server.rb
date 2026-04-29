# frozen_string_literal: true

module GemDocs
  module MCP
    class Server
      def self.start(_arguments = [], out: $stdout, err: $stderr)
        require "fast_mcp"

        out.puts "gem-docs-server placeholder loaded"
        0
      rescue LoadError
        err.puts "gem-docs-server requires the optional fast-mcp gem."
        1
      end
    end
  end
end
