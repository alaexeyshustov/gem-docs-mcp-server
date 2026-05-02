# frozen_string_literal: true

require "json"

module GemDocs
  module Formatters
    module Context
      class Json < Base
        def call(gems:)
          JSON.pretty_generate({ gems: documented_gems(gems) })
        end
      end
    end
  end
end
