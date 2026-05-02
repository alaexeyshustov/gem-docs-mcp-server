# frozen_string_literal: true

module GemDocs
  module Formatters
    module_function

    def for(format)
      case format.to_s
      when "json"
        Json.new
      when "text"
        Text.new
      else
        raise ArgumentError, "Unsupported formatter: #{format}"
      end
    end
  end
end
