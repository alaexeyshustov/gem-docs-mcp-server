# frozen_string_literal: true

module GemDocs
  module MCP
    module Tools
      class Classes < GemDocs::MCP::CommandTool
        tool_name "classes"
        description "List documented classes and modules as the CLI JSON payload"
        command GemDocs::Commands::Classes

        arguments do
          required(:gem_name).filled(:string).description("Gem name to inspect")
          optional(:version).filled(:string).description("Optional gem version")
        end
      end
    end
  end
end
