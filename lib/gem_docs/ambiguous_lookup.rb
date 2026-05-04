# frozen_string_literal: true

module GemDocs
  class AmbiguousLookup < Error
    attr_reader :candidates

    def initialize(path, candidates:)
      @candidates = candidates
      super("Multiple matches found for '#{path}'")
    end

    def error_code
      "ambiguous"
    end

    def to_h
      { error: error_code, message: message, candidates: candidates }
    end
  end
end
