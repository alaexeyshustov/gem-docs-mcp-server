# frozen_string_literal: true

module GemDocs
  class LookupNotFound < Error
    def initialize(path, message: nil)
      super(message || "No method matching '#{path}'")
    end

    def error_code
      "not_found"
    end
  end
end
