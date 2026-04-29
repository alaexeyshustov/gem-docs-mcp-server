# frozen_string_literal: true

module GemDocs
  module Commands
    class Server < Base
      def call(arguments = [])
        require "gem_docs/mcp/server"

        GemDocs::MCP::Server.start(arguments, out: out, err: err)
      end
    end
  end
end
