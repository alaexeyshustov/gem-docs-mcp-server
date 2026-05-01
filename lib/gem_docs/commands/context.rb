# frozen_string_literal: true

module GemDocs
  module Commands
    class Context < Base
      desc "Show project gem context"

      def call(**)
        placeholder("context")
      end
    end
  end
end
