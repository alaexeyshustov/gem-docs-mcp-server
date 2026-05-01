# frozen_string_literal: true

module GemDocs
  module Commands
    class Server < Base
      desc "Start the MCP server"
      argument :args, type: :array

      def call(args: [], **)
        require "gem_docs/mcp/server"

        exit GemDocs::MCP::Server.start(args, out: out, err: err)
      end
    end
  end
end
