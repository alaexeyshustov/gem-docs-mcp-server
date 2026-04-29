# frozen_string_literal: true

module GemDocs
  module Commands
    class Summary < Base
      def call(_arguments = [])
        placeholder("summary")
      end
    end
  end
end
