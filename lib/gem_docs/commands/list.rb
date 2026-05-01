# frozen_string_literal: true

module GemDocs
  module Commands
    class List < Base
      desc "Show installed gems"

      def call(**)
        placeholder("list")
      end
    end
  end
end
