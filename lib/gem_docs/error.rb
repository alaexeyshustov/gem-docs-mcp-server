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
      { error: error_code, message: message }.tap do |payload|
        payload[:details] = details unless details.empty?
      end
    end
  end
end
