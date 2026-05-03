# frozen_string_literal: true

require "json"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Formatters::Json do
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
    it "serializes registry entries without requiring hash access" do
      formatter = described_class.new

      output = formatter.classes(
        gem: "rack",
        entries: [
          build_entry(path: "Rack::Builder"),
          build_entry(path: "Rack::Request", docstring: "Request wrapper")
        ]
      )

      expect(JSON.parse(output)).to eq(
        "gem" => "rack",
        "classes" => [
          {
            "path" => "Rack::Builder",
            "name" => "Builder",
            "kind" => "class",
            "visibility" => "public",
            "signature" => "Rack::Builder",
            "doc_source" => "yard"
          },
          {
            "path" => "Rack::Request",
            "name" => "Request",
            "kind" => "class",
            "visibility" => "public",
            "docstring" => "Request wrapper",
            "signature" => "Rack::Request",
            "doc_source" => "yard"
          }
        ]
      )
    end
  end

  describe "#lookup" do
    it "serializes registry entries without requiring hash access" do
      formatter = described_class.new

      output = formatter.lookup(
        result: build_entry(
          path: "Rack::Builder",
          signature: "Rack::Builder",
          docstring: "Builds Rack applications"
        )
      )

      expect(JSON.parse(output)).to eq(
        "path" => "Rack::Builder",
        "name" => "Builder",
        "kind" => "class",
        "visibility" => "public",
        "docstring" => "Builds Rack applications",
        "signature" => "Rack::Builder",
        "doc_source" => "yard"
      )
    end
  end

  describe "#search" do
    it "serializes registry entries without requiring hash access" do
      formatter = described_class.new

      output = formatter.search(
        results: [
          build_entry(path: "Rack::Builder"),
          build_entry(path: "Rack::Request")
        ]
      )

      expect(JSON.parse(output)).to eq(
        [
          {
            "path" => "Rack::Builder",
            "name" => "Builder",
            "kind" => "class",
            "visibility" => "public",
            "signature" => "Rack::Builder",
            "doc_source" => "yard"
          },
          {
            "path" => "Rack::Request",
            "name" => "Request",
            "kind" => "class",
            "visibility" => "public",
            "signature" => "Rack::Request",
            "doc_source" => "yard"
          }
        ]
      )
    end
  end
end
