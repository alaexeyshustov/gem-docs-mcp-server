# frozen_string_literal: true

module GemDocs
  module Commands
    class Search < Base
      desc "Search gem documentation"

      def call(**_kwargs)
        placeholder("search")
      end
    end
  end
end
