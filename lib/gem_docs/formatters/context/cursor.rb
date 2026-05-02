# frozen_string_literal: true

module GemDocs
  module Formatters
    module Context
      class Cursor < Base
        def call(gems:)
          [ "# Cursor gem context", gem_sections(gems) ].flatten.join("\n\n")
        end
      end
    end
  end
end
