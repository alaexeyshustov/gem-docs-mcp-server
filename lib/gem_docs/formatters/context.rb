# frozen_string_literal: true

module GemDocs
  module Formatters
    module Context
      FORMATTERS = {
        "claude" => "Claude",
        "cursor" => "Cursor",
        "windsurf" => "Windsurf",
        "copilot" => "Copilot",
        "json" => "Json"
      }.freeze

      module_function

      def for(format)
        const_get(FORMATTERS.fetch(format.to_s), false).new
      rescue KeyError
        raise ArgumentError, "Unsupported context formatter: #{format}"
      end
    end
  end
end
