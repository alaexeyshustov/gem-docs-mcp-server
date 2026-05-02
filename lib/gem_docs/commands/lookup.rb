# frozen_string_literal: true

module GemDocs
  module Commands
    class Lookup < Base
      desc "Look up a constant or method"

      def call(**_kwargs)
        placeholder("lookup")
      end
    end
  end
end
