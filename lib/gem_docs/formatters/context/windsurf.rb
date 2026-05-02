# frozen_string_literal: true

module GemDocs
  module Formatters
    module Context
      class Windsurf < Base
        def call(gems:)
          [ "# Windsurf gem context", gem_sections(gems) ].flatten.join("\n\n")
        end
      end
    end
  end
end
