# frozen_string_literal: true

require "json"

module GemDocs
  module Formatters
    class Json
      def call(payload)
        JSON.pretty_generate(payload)
      end
    end
  end
end
