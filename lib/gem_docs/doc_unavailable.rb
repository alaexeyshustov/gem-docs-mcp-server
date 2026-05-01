# frozen_string_literal: true

module GemDocs
  class DocUnavailable < Error
    def initialize(subject, message: nil, details: {})
      super(message || "Documentation is unavailable for '#{subject}'", details: details)
    end

    def error_code
      "unavailable"
    end
  end
end
