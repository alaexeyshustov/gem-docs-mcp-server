# frozen_string_literal: true

module GemDocs
  module Commands
    class Server < Base
      desc "Start the MCP server"
      option :mode,
             values: %w[stdio http],
             default: "stdio",
             desc: "Server transport mode"
      option :port,
             default: "6040",
             desc: "HTTP port"
      option :bind_all,
             type: :boolean,
             default: false,
             desc: "Bind HTTP mode to 0.0.0.0"

      def call(mode: "stdio", port: "6040", bind_all: false, **_kwargs)
        require "gem_docs/mcp/server"

        GemDocs::MCP::Server.start(server_arguments(mode: mode, port: port, bind_all: bind_all), out: out, err: err)
      end

      private

      def server_arguments(mode:, port:, bind_all:)
        arguments = [ "--mode", mode.to_s, "--port", port.to_s ]
        arguments << "--bind-all" if bind_all
        arguments
      end
    end
  end
end
