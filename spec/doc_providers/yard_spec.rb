# frozen_string_literal: true

require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::DocProviders::Yard do
  describe "#available?" do
    it "detects gem-local .yardoc registries" do
      with_yard_fixture_gem("yard_available", source: "module YardAvailable; end\n") do |spec|
        expect(described_class.new(loaded_gem_builder: ->(*) { raise "unused" }).available?(spec)).to eq(true)
      end
    end
  end

  describe "#load" do
    it "normalizes YARD objects into loaded gem entries" do
      with_yard_fixture_gem("well_documented", source: <<~RUBY) do |spec|
        module WellDocumented
          class Widget
            # Performs work.
            #
            # @param input [String]
            # @return [String]
            def call(input)
            end
          end
        end
      RUBY
        registry = GemDocs::DocRegistry.new(cache: false)
        provider = described_class.new(
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source|
            registry.send(:build_source_loaded_gem, resolved_spec, objects: objects, doc_source: doc_source)
          end
        )

        loaded_gem = provider.load(spec)

        expect(loaded_gem.doc_source).to eq(:yard)
        expect(loaded_gem.entry_points).to include("WellDocumented::Widget#call")
        expect(loaded_gem.objects.find { |object| object.path == "WellDocumented::Widget#call" })
          .to have_attributes(
            kind: :instance_method,
            signature: "def call(input)",
            docstring: "Performs work.",
            doc_source: :yard,
            tags: {
              param: [ include(name: "input", types: [ "String" ]) ],
              return: [ include(types: [ "String" ]) ]
            }
          )
      end
    end
  end
end
