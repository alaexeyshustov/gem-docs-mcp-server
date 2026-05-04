# frozen_string_literal: true

require "json"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Formatters::Json do
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

  describe ".for" do
    it "resolves the shared formatter instance by format" do
      expect(GemDocs::Formatters.for("json")).to be_a(described_class)
      expect(GemDocs::Formatters.for("text")).to be_a(GemDocs::Formatters::Text)
    end
  end

  describe "#error" do
    it "renders compact structured errors without empty fields" do
      formatter = described_class.new

      output = formatter.error(
        error: "not_found",
        message: "Gem 'missing-gem' is not installed",
        details: {}
      )

      expect(JSON.parse(output)).to eq(
        "error" => "not_found",
        "message" => "Gem 'missing-gem' is not installed"
      )
    end
  end

  describe "#list" do
    it "omits empty values from gem payloads while preserving required fields" do
      formatter = described_class.new

      output = formatter.list(
        gems: [
          { name: "rack", version: "3.1.0", doc_source: :yard, summary: "HTTP toolkit" },
          { name: "rbs", version: "3.4.0", doc_source: :source_only, summary: "" }
        ]
      )

      expect(JSON.parse(output)).to eq(
        [
          {
            "name" => "rack",
            "version" => "3.1.0",
            "doc_source" => "yard",
            "summary" => "HTTP toolkit"
          },
          {
            "name" => "rbs",
            "version" => "3.4.0",
            "doc_source" => "source_only"
          }
        ]
      )
    end
  end

  describe "#summary" do
    it "serializes LoadedGem objects returned by the registry" do
      formatter = described_class.new
      loaded_gem = build_loaded_gem(
        name: "rack",
        version: "3.1.0",
        summary: "HTTP toolkit",
        homepage: "https://example.test/rack",
        license: "MIT",
        doc_source: :yard,
        entry_points: [ "Rack.new" ],
        objects: [
          build_entry(path: "Rack::Builder"),
          build_entry(path: "Rack::Request")
        ]
      )

      output = formatter.summary(gem: loaded_gem)

      expect(JSON.parse(output)).to eq(
        "name" => "rack",
        "version" => "3.1.0",
        "description" => "HTTP toolkit",
        "homepage" => "https://example.test/rack",
        "license" => "MIT",
        "doc_source" => "yard",
        "classes" => [ "Rack::Builder", "Rack::Request" ],
        "entry_points" => [ "Rack.new" ]
      )
    end

    it "preserves empty entry points for source-only gems" do
      formatter = described_class.new
      loaded_gem = build_loaded_gem(
        name: "source-only",
        version: "0.1.0",
        summary: "Fallback docs",
        doc_source: :source_only,
        objects: [ build_entry(path: "SourceOnly::Widget") ]
      )

      output = formatter.summary(gem: loaded_gem)

      expect(JSON.parse(output)).to include(
        "name" => "source-only",
        "entry_points" => []
      )
    end
  end

  describe "#classes" do
    it "serializes class listing payloads using the public contract" do
      formatter = described_class.new

      output = formatter.classes(
        entries: [
          {
            name: "Rack::Builder",
            type: "class",
            superclass: "Object",
            summary: "",
            method_count: 2
          },
          {
            name: "Rack::Request",
            type: "module",
            summary: "Request wrapper",
            method_count: 1
          }
        ]
      )

      expect(JSON.parse(output)).to eq(
        [
          {
            "name" => "Rack::Builder",
            "type" => "class",
            "superclass" => "Object",
            "summary" => "",
            "method_count" => 2
          },
          {
            "name" => "Rack::Request",
            "type" => "module",
            "summary" => "Request wrapper",
            "method_count" => 1
          }
        ]
      )
    end
  end

  describe "#lookup" do
    it "serializes lookup payloads while preserving empty docstrings and aliases" do
      formatter = described_class.new

      output = formatter.lookup(
        result: {
          path: "Rack::Builder",
          gem: "rack",
          version: "3.1.0",
          doc_source: :yard,
          signature: "def build(app = nil)",
          visibility: :public,
          docstring: "",
          tags: {
            example: [ "Rack::Builder.new" ]
          },
          aliases: []
        }
      )

      expect(JSON.parse(output)).to eq(
        "path" => "Rack::Builder",
        "gem" => "rack",
        "version" => "3.1.0",
        "doc_source" => "yard",
        "signature" => "def build(app = nil)",
        "visibility" => "public",
        "docstring" => "",
        "tags" => {
          "example" => [ "Rack::Builder.new" ]
        },
        "aliases" => []
      )
    end
  end

  describe "#search" do
    it "serializes ranked search results with their documented fields" do
      formatter = described_class.new

      output = formatter.search(
        results: [
          { path: "Rack::Builder#call", gem: "rack", type: "method", summary: "Builds Rack apps", score: 0.95 },
          { path: "Rack::Request", gem: "rack", type: "class", summary: "", score: 0.72 }
        ]
      )

      expect(JSON.parse(output)).to eq(
        [
          {
            "path" => "Rack::Builder#call",
            "gem" => "rack",
            "type" => "method",
            "summary" => "Builds Rack apps",
            "score" => 0.95
          },
          {
            "path" => "Rack::Request",
            "gem" => "rack",
            "type" => "class",
            "summary" => "",
            "score" => 0.72
          }
        ]
      )
    end
  end
end
