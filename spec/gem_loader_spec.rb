# frozen_string_literal: true

require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::GemLoader do
  describe "#resolve_spec!" do
    it "returns the requested gem spec when it exists" do
      with_source_fixture_gem("source_only", source: "module SourceOnly; end\n") do |spec|
        loader = described_class.new(
          spec_resolver: GemDocs::DocRegistry.method(:gem_spec_for),
          doc_source_detector: ->(_resolved_spec) { raise "unused" },
          source_loader: ->(_resolved_spec) { raise "unused" },
          loaded_gem_builder: ->(_resolved_spec, _objects, _doc_source) { raise "unused" }
        )

        expect(loader.resolve_spec!("source_only")).to eq(spec)
      end
    end

    it "raises GemDocs::GemNotFound when the gem cannot be resolved" do
      loader = described_class.new(
        spec_resolver: ->(_name, version: nil) { nil },
        doc_source_detector: ->(_resolved_spec) { raise "unused" },
        source_loader: ->(_resolved_spec) { raise "unused" },
        loaded_gem_builder: ->(_resolved_spec, _objects, _doc_source) { raise "unused" }
      )

      expect { loader.resolve_spec!("missing-gem") }.to raise_error(GemDocs::GemNotFound)
    end
  end

  describe "#detect_source" do
    it "detects the YARD path through the YARD provider" do
      with_yard_fixture_gem("well_documented", source: "module WellDocumented; end\n") do |spec|
        registry = GemDocs::DocRegistry.new(cache: false)
        yard_provider = GemDocs::DocProviders::Yard.new(
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source|
            registry.send(:build_source_loaded_gem, resolved_spec, objects: objects, doc_source: doc_source)
          end
        )
        loader = described_class.new(
          spec_resolver: GemDocs::DocRegistry.method(:gem_spec_for),
          doc_source_detector: registry.method(:detect_doc_source),
          source_loader: registry.method(:load_source_objects),
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source|
            registry.send(:build_source_loaded_gem, resolved_spec, objects: objects, doc_source: doc_source)
          end,
          yard_provider: yard_provider
        )

        expect(loader.detect_source(spec)).to eq(:yard)
      end
    end

    it "detects the source-only fallback path" do
      with_source_fixture_gem("source_only", source: <<~RUBY) do |spec|
        module SourceOnly
          class Widget
            def call
            end
          end
        end
      RUBY
        registry = GemDocs::DocRegistry.new(cache: false)
        loader = described_class.new(
          spec_resolver: GemDocs::DocRegistry.method(:gem_spec_for),
          doc_source_detector: registry.method(:detect_doc_source),
          source_loader: registry.method(:load_source_objects),
          loaded_gem_builder: ->(_resolved_spec, _objects, _doc_source) { raise "unused" }
        )

        expect(loader.detect_source(spec)).to eq(:source_only)
      end
    end

    it "detects gems with no documentable objects" do
      with_empty_fixture_gem("empty_fixture") do |spec|
        registry = GemDocs::DocRegistry.new(cache: false)
        loader = described_class.new(
          spec_resolver: GemDocs::DocRegistry.method(:gem_spec_for),
          doc_source_detector: registry.method(:detect_doc_source),
          source_loader: registry.method(:load_source_objects),
          loaded_gem_builder: ->(_resolved_spec, _objects, _doc_source) { raise "unused" }
        )

        expect(loader.detect_source(spec)).to eq(:none)
      end
    end
  end

  describe "#load" do
    it "builds a loaded gem for YARD-backed gems through the YARD provider" do
      with_yard_fixture_gem("well_documented", source: <<~RUBY) do
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
        yard_provider = GemDocs::DocProviders::Yard.new(
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source|
            registry.send(:build_source_loaded_gem, resolved_spec, objects: objects, doc_source: doc_source)
          end
        )
        loader = described_class.new(
          spec_resolver: GemDocs::DocRegistry.method(:gem_spec_for),
          doc_source_detector: registry.method(:detect_doc_source),
          source_loader: registry.method(:load_source_objects),
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source|
            registry.send(:build_source_loaded_gem, resolved_spec, objects: objects, doc_source: doc_source)
          end,
          yard_provider: yard_provider
        )

        loaded_gem = loader.load("well_documented")

        expect(loaded_gem.doc_source).to eq(:yard)
        expect(loaded_gem.entry_points).to include("WellDocumented::Widget#call")
        expect(loaded_gem.objects.find { |object| object.path == "WellDocumented::Widget#call" }&.docstring)
          .to include("Performs work.")
      end
    end

    it "builds a loaded gem for source-only gems" do
      with_source_fixture_gem("source_only", source: <<~RUBY) do
        module SourceOnly
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        registry = GemDocs::DocRegistry.new(cache: false)
        loader = described_class.new(
          spec_resolver: GemDocs::DocRegistry.method(:gem_spec_for),
          doc_source_detector: registry.method(:detect_doc_source),
          source_loader: registry.method(:load_source_objects),
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source|
            registry.send(:build_source_loaded_gem, resolved_spec, objects: objects, doc_source: doc_source)
          end
        )

        loaded_gem = loader.load("source_only")

        expect(loaded_gem.doc_source).to eq(:source_only)
        expect(loaded_gem.objects.map(&:path)).to include("SourceOnly", "SourceOnly::Widget", "SourceOnly::Widget#call")
      end
    end

    it "builds an empty loaded gem for gems with no documentable objects" do
      with_empty_fixture_gem("empty_fixture") do
        registry = GemDocs::DocRegistry.new(cache: false)
        loader = described_class.new(
          spec_resolver: GemDocs::DocRegistry.method(:gem_spec_for),
          doc_source_detector: registry.method(:detect_doc_source),
          source_loader: registry.method(:load_source_objects),
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source|
            registry.send(:build_source_loaded_gem, resolved_spec, objects: objects, doc_source: doc_source)
          end
        )

        loaded_gem = loader.load("empty_fixture")

        expect(loaded_gem.doc_source).to eq(:none)
        expect(loaded_gem.objects).to eq([])
        expect(loaded_gem.entry_points).to eq([])
      end
    end
  end

  describe "#load_fallback" do
    it "builds fallback loaded gems without re-detecting the doc source" do
      with_source_fixture_gem("source_only", source: <<~RUBY) do |spec|
        module SourceOnly
          class Widget
            def call(input)
            end
          end
        end
      RUBY
        registry = GemDocs::DocRegistry.new(cache: false)
        loader = described_class.new(
          spec_resolver: GemDocs::DocRegistry.method(:gem_spec_for),
          doc_source_detector: ->(_resolved_spec) { raise "unused" },
          source_loader: registry.method(:load_source_objects),
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source|
            registry.send(:build_source_loaded_gem, resolved_spec, objects: objects, doc_source: doc_source)
          end
        )

        loaded_gem = loader.load_fallback(spec)

        expect(loaded_gem.doc_source).to eq(:source_only)
        expect(loaded_gem.objects.map(&:path)).to include("SourceOnly", "SourceOnly::Widget", "SourceOnly::Widget#call")
      end
    end
  end
end
