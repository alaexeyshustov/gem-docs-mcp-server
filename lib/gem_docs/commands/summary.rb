# frozen_string_literal: true

module GemDocs
  module Commands
    class Summary < Base
      desc "Summarize a gem"

      def call(**_kwargs)
        placeholder("summary")
      end
    end
  end
end
