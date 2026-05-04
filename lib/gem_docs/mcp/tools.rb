# frozen_string_literal: true

module GemDocs
  module MCP
    module Tools
      module_function
    end
  end
end

require "gem_docs/mcp/tools/classes"
require "gem_docs/mcp/tools/list"
require "gem_docs/mcp/tools/lookup"
require "gem_docs/mcp/tools/search"
require "gem_docs/mcp/tools/summary"

module GemDocs
  module MCP
    module Tools
      def self.all
        [ List, Summary, Classes, Lookup, Search ]
      end
    end
  end
end
