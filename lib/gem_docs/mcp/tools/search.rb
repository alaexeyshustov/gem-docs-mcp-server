# frozen_string_literal: true

module GemDocs
  module MCP
    module Tools
      class Search < GemDocs::MCP::CommandTool
        tool_name "search"
        description "Search gem documentation as the CLI JSON payload"
        command GemDocs::Commands::Search

        arguments do
          required(:query).filled(:string).description("Query to search for")
          optional(:gem).filled(:string).description("Optional gem name to search within")
          optional(:scope).filled(:string).description("Search scope: methods, classes, or all")
          optional(:limit).filled(:integer).description("Maximum number of results")
        end
      end
    end
  end
end
