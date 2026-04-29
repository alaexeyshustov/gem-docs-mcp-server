# frozen_string_literal: true

module GemDocs
  module Formatters
    class Text
      def call(payload)
        payload.to_s
      end
    end
  end
end
