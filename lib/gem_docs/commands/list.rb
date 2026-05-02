# frozen_string_literal: true

module GemDocs
  module Commands
    class List < Base
      desc "Show installed gems"

      def call(**_kwargs)
        placeholder("list")
      end
    end
  end
end
