# frozen_string_literal: true

module GemDocs
  class Error < StandardError
    attr_reader :details

    def initialize(message, details: {})
      super(message)
      @details = details
    end

    def error_code
      raise NotImplementedError
    end

    def to_h
      return { error: error_code, message: message } if details.empty?

      { error: error_code, message: message, details: details }
    end
  end
end
