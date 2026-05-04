# frozen_string_literal: true

module GemDocs
  module MCP
    module Tools
      class List < GemDocs::MCP::CommandTool
        tool_name "list"
        description "List installed gems as the CLI JSON payload"
        command GemDocs::Commands::List
      end
    end
  end
end
