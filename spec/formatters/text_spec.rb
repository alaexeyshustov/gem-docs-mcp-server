# frozen_string_literal: true

require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Formatters::Text do
  def build_entry(path:, signature: path, docstring: "", source_location: nil, kind: :class, tags: {}, aliases: [])
    GemDocs::DocRegistry::Entry.new(
      path: path,
      name: path.split(/[:#.]/).last,
      kind: kind,
      visibility: :public,
      docstring: docstring,
      signature: signature,
      source_location: source_location,
      superclass: nil,
      doc_source: :yard,
      tags: tags,
      aliases: aliases
    )
  end

  def build_loaded_gem(name:, version:, summary:, doc_source:, objects:, homepage: nil, license: nil, entry_points: [])
    GemDocs::DocRegistry::LoadedGem.new(
      name: name,
      version: version,
      summary: summary,
      homepage: homepage,
      license: license,
      path: "/tmp/#{name}",
      doc_source: doc_source,
      objects: objects,
      entry_points: entry_points
    )
  end

  describe "#list" do
    it "renders aligned gem rows for CLI output" do
      formatter = described_class.new

      output = formatter.list(
        gems: [
          { name: "rack", version: "3.1.0", doc_source: :yard, summary: "HTTP toolkit" },
          { name: "rbs", version: "3.4.0", doc_source: :source_only, summary: "" }
        ]
      )

      expect(output.lines).to eq(
        [
          "NAME  VERSION  DOC SOURCE   SUMMARY\n",
          "rack  3.1.0    yard         HTTP toolkit\n",
          "rbs   3.4.0    source_only\n"
        ]
      )
    end
  end

  describe "#summary" do
    it "renders a LoadedGem returned by the registry" do
      formatter = described_class.new
      loaded_gem = build_loaded_gem(
        name: "rack",
        version: "3.1.0",
        summary: "HTTP toolkit",
        doc_source: :yard,
        entry_points: [ "Rack.new", "Rack::Builder#call" ],
        objects: [
          build_entry(path: "Rack::Builder"),
          build_entry(path: "Rack::Request")
        ]
      )

      output = formatter.summary(gem: loaded_gem)

      expect(output).to eq(
        "rack 3.1.0 [yard]\n" \
        "HTTP toolkit\n" \
        "Classes: Rack::Builder, Rack::Request\n" \
        "Entry points:\n" \
        "  Rack.new\n" \
        "  Rack::Builder#call"
      )
    end
  end

  describe "#classes" do
    it "renders aligned text rows for the class listing contract" do
      formatter = described_class.new

      output = formatter.classes(
        entries: [
          {
            name: "Rack::Builder",
            type: "class",
            summary: "",
            method_count: 12
          },
          {
            name: "Rack::Request",
            type: "module",
            summary: "Request wrapper",
            method_count: 1
          }
        ]
      )

      expect(output).to eq(
        "Rack::Builder  class   (12 methods)\n" \
        "Rack::Request  module  (1 method)    Request wrapper"
      )
    end
  end

  describe "#lookup" do
    it "renders lookup metadata, tags, and aliases" do
      formatter = described_class.new

      output = formatter.lookup(
        result: {
          path: "Rack::Builder",
          gem: "rack",
          version: "3.1.0",
          doc_source: :yard,
          signature: "def build(app = nil)",
          docstring: "Builds Rack applications",
          tags: {
            param: [
              { name: "app", types: [ "Rack::App" ], text: "Rack app" }
            ],
            example: [ "Rack::Builder.new" ]
          },
          aliases: [ "Rack::Builder.compile" ]
        }
      )

      expect(output).to eq(
        "Rack::Builder  [rack 3.1.0 · yard]\n" \
        "def build(app = nil)\n" \
        "Builds Rack applications\n" \
        "Params:\n" \
        "  app  Rack::App  Rack app\n" \
        "Example:\n" \
        "  Rack::Builder.new\n" \
        "Aliases: Rack::Builder.compile"
      )
    end

    it "renders compressed insight details even when a title is missing" do
      formatter = described_class.new

      output = formatter.lookup(
        result: {
          path: "Rack::Builder",
          gem: "rack",
          version: "3.1.0",
          doc_source: :yard,
          signature: "def build(app = nil)",
          docstring: "Builds Rack applications",
          knowledge_source: :compressed,
          non_obvious_insights: [
            { "detail" => "Builder freezes middleware order after map is evaluated." }
          ],
          tags: {},
          aliases: []
        }
      )

      expect(output).to include("Knowledge source: compressed")
      expect(output).to include("Non-obvious insights:")
      expect(output).to include("  Builder freezes middleware order after map is evaluated.")
      expect(output).not_to include("  - :")
    end
  end

  describe "#search" do
    it "renders ranked search rows with gem, score, and summary" do
      formatter = described_class.new

      output = formatter.search(
        results: [
          { path: "Rack::Builder#call", gem: "rack", type: "method", summary: "Builds Rack apps", score: 0.95 },
          { path: "Rack::Request", gem: "rack", type: "class", summary: "Represents a Rack request", score: 0.72 }
        ]
      )

      expect(output).to eq(
        "Rack::Builder#call  rack  0.95  Builds Rack apps\n" \
        "Rack::Request       rack  0.72  Represents a Rack request"
      )
    end

    it "treats nil scores as 0.00" do
      formatter = described_class.new

      output = formatter.search(
        results: [
          { path: "Rack::Builder#call", gem: "rack", score: nil, summary: "Builds Rack apps" }
        ]
      )

      expect(output).to eq("Rack::Builder#call  rack  0.00  Builds Rack apps")
    end
  end
end
