# frozen_string_literal: true

module GemDocs
  module Formatters
    module Context
      class Copilot < Base
        def call(gems:)
          [ "# Copilot gem context", gem_sections(gems) ].flatten.join("\n\n")
        end
      end
    end
  end
end
