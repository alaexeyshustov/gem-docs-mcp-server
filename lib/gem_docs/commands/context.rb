# frozen_string_literal: true

module GemDocs
  module Commands
    class Context < Base
      def call(_arguments = [])
        placeholder("context")
      end
    end
  end
end
