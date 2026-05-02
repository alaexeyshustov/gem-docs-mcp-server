# frozen_string_literal: true

module GemDocs
  module Commands
    class Classes < Base
      desc "List documented classes"

      def call(**_kwargs)
        placeholder("classes")
      end
    end
  end
end
