# frozen_string_literal: true

module GemDocs
  class GemNotFound < Error
    def initialize(gem_name, message: nil, details: {})
      super(message || "Gem '#{gem_name}' is not installed", details: details)
    end

    def error_code
      "not_found"
    end
  end
end
