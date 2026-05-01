# frozen_string_literal: true

module GemDocs
  class RegistryError < Error
    def initialize(message = "The gem documentation registry is unavailable", details: {})
      super(message, details: details)
    end

    def error_code
      "registry_error"
    end
  end
end
