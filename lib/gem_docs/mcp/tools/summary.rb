# frozen_string_literal: true

module GemDocs
  module MCP
    module Tools
      class Summary < GemDocs::MCP::CommandTool
        tool_name "summary"
        description "Summarize a gem as the CLI JSON payload"
        command GemDocs::Commands::Summary

        arguments do
          required(:gem_name).filled(:string).description("Gem name to summarize")
          optional(:version).filled(:string).description("Optional gem version")
        end
      end
    end
  end
end
