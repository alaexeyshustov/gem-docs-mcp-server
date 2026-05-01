# frozen_string_literal: true

module GemDocs
  class ConfigurationError < Error
    def error_code
      "configuration_error"
    end
  end
end
