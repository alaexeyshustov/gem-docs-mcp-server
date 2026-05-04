# frozen_string_literal: true

module GemDocs
  module MCP
    module Tools
      class Lookup < GemDocs::MCP::CommandTool
        tool_name "lookup"
        description "Look up a constant or method as the CLI JSON payload"
        command GemDocs::Commands::Lookup

        arguments do
          required(:path).filled(:string).description("Constant or method path to resolve")
          optional(:gem).filled(:string).description("Optional gem name to scope the lookup")
        end
      end
    end
  end
end
