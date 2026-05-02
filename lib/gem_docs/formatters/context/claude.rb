# frozen_string_literal: true

module GemDocs
  module Formatters
    module Context
      class Claude < Base
        def call(gems:)
          [ "# Gem documentation context", gem_sections(gems) ].flatten.join("\n\n")
        end
      end
    end
  end
end
