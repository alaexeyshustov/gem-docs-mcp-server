# frozen_string_literal: true

require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Formatters::Text do
  def build_entry(path:, signature: path, docstring: "", source_location: nil, kind: :class)
    GemDocs::DocRegistry::Entry.new(
      path: path,
      name: path.split(/[:#.]/).last,
      kind: kind,
      visibility: :public,
      docstring: docstring,
      signature: signature,
      source_location: source_location,
      superclass: nil,
      doc_source: :yard
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
    it "omits the source line when the entry has no source location" do
      formatter = described_class.new

      output = formatter.lookup(
        result: build_entry(
          path: "Rack::Builder",
          signature: "Rack::Builder",
          docstring: "Builds Rack applications"
        )
      )

      expect(output).to eq("Rack::Builder\nRack::Builder\nBuilds Rack applications")
    end
  end

  describe "#search" do
    it "renders registry entries without requiring hash access" do
      formatter = described_class.new

      output = formatter.search(
        results: [
          build_entry(path: "Rack::Builder"),
          build_entry(path: "Rack::Request")
        ]
      )

      expect(output).to eq("- Rack::Builder\n- Rack::Request")
    end
  end
end
