# frozen_string_literal: true

require "json"
require "stringio"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Commands::Search do
  def build_entry(path:, kind: :class, visibility: :public, docstring: "")
    GemDocs::DocRegistry::Entry.new(
      path: path,
      name: path.split(/[:#.]/).last,
      kind: kind,
      visibility: visibility,
      docstring: docstring,
      signature: path,
      source_location: nil,
      superclass: nil,
      doc_source: :yard,
      tags: {},
      aliases: []
    )
  end

  def build_loaded_gem(name:, version: "1.0.0", doc_source: :yard, objects:)
    GemDocs::DocRegistry::LoadedGem.new(
      name: name,
      version: version,
      summary: "#{name} fixture",
      path: "/tmp/#{name}",
      doc_source: doc_source,
      objects: objects
    )
  end

  def build_spec(name)
    instance_double(Gem::Specification, name: name)
  end

  let(:stdout) { StringIO.new }
  let(:command) { described_class.new }
  let(:registry) { instance_double(GemDocs::DocRegistry) }
  let(:config) { instance_double(GemDocs::Config, exclude_gems: []) }

  before do
    allow(command).to receive(:out).and_return(stdout)
    allow(command).to receive(:doc_registry).and_return(registry)
    allow(command).to receive(:config).and_return(config)
  end

  describe "within a single gem (--gem flag)" do
    it "returns results sorted by descending score with documented JSON fields" do
      allow(registry).to receive(:load_gem).with("example").and_return(
        build_loaded_gem(
          name: "example",
          objects: [
            build_entry(path: "Example::Widget", docstring: "The primary widget."),
            build_entry(path: "Example::WidgetBuilder", docstring: "Builds widgets.")
          ]
        )
      )

      status = command.call(query: "Widget", gem: "example", format: "json")

      expect(status).to eq(0)
      payload = JSON.parse(stdout.string)

      expect(payload.size).to eq(2)
      expect(payload[0]).to include(
        "path" => "Example::Widget",
        "gem" => "example",
        "type" => "class",
        "summary" => "The primary widget."
      )
      expect(payload[1]).to include(
        "path" => "Example::WidgetBuilder",
        "gem" => "example",
        "type" => "class",
        "summary" => "Builds widgets."
      )
      expect(payload[0].fetch("score")).to be > 0
      expect(payload[1].fetch("score")).to be > 0
      expect(payload[0].fetch("score")).to be > payload[1].fetch("score")
    end

    it "respects --limit" do
      allow(registry).to receive(:load_gem).with("example").and_return(
        build_loaded_gem(
          name: "example",
          objects: [
            build_entry(path: "Example::Widget"),
            build_entry(path: "Example::WidgetBuilder"),
            build_entry(path: "Example::WidgetFactory")
          ]
        )
      )

      status = command.call(query: "Widget", gem: "example", limit: 2, format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string).map { |result| result.fetch("path") }).to eq(
        [ "Example::Widget", "Example::WidgetBuilder" ]
      )
    end

    it "--scope methods returns only method entries" do
      allow(registry).to receive(:load_gem).with("example").and_return(
        build_loaded_gem(
          name: "example",
          objects: [
            build_entry(path: "Example::Worker", docstring: "Worker class"),
            build_entry(path: "Example::Worker#call", kind: :instance_method, docstring: "Calls the worker."),
            build_entry(path: "Example::Worker.build", kind: :class_method, docstring: "Builds workers.")
          ]
        )
      )

      status = command.call(query: "Worker", gem: "example", scope: "methods", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to all(include("type" => "method"))
    end

    it "--scope classes returns only class/module entries" do
      allow(registry).to receive(:load_gem).with("example").and_return(
        build_loaded_gem(
          name: "example",
          objects: [
            build_entry(path: "Example::Worker", docstring: "Worker class"),
            build_entry(path: "Example::Worker#call", kind: :instance_method, docstring: "Calls the worker."),
            build_entry(path: "Example::Workers", kind: :module, docstring: "Workers module.")
          ]
        )
      )

      status = command.call(query: "Worker", gem: "example", scope: "classes", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string).map { |result| result.fetch("path") }).to eq(
        [ "Example::Worker", "Example::Workers" ]
      )
    end

    it "--scope all returns both class and method matches" do
      allow(registry).to receive(:load_gem).with("example").and_return(
        build_loaded_gem(
          name: "example",
          objects: [
            build_entry(path: "Example::Worker", docstring: "Worker class"),
            build_entry(path: "Example::Worker#call", kind: :instance_method, docstring: "Calls the worker.")
          ]
        )
      )

      status = command.call(query: "Worker", gem: "example", scope: "all", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string).map { |result| result.fetch("path") }).to eq(
        [ "Example::Worker", "Example::Worker#call" ]
      )
    end

    it "gives higher score to exact name matches than substring matches" do
      allow(registry).to receive(:load_gem).with("example").and_return(
        build_loaded_gem(
          name: "example",
          objects: [
            build_entry(path: "Example::Widget", docstring: "Exact match"),
            build_entry(path: "Example::WidgetBuilder", docstring: "Partial match")
          ]
        )
      )

      command.call(query: "Widget", gem: "example", format: "json")

      payload = JSON.parse(stdout.string)
      expect(payload[0].fetch("path")).to eq("Example::Widget")
      expect(payload[0].fetch("score")).to be > payload[1].fetch("score")
    end

    it "returns an empty array when nothing matches" do
      allow(registry).to receive(:load_gem).with("example").and_return(
        build_loaded_gem(name: "example", objects: [ build_entry(path: "Example::Widget") ])
      )

      status = command.call(query: "missing", gem: "example", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to eq([])
    end

    it "raises for an unknown gem" do
      allow(registry).to receive(:load_gem).with("missing").and_raise(GemDocs::GemNotFound.new("missing"))

      expect { command.call(query: "widget", gem: "missing", format: "json") }
        .to raise_error(GemDocs::GemNotFound, "Gem 'missing' is not installed")
    end

    it "handles a gem with doc_source: none gracefully" do
      allow(registry).to receive(:load_gem).with("empty").and_return(
        build_loaded_gem(name: "empty", doc_source: :none, objects: [])
      )

      status = command.call(query: "widget", gem: "empty", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to eq([])
    end
  end

  describe "across all gems (no --gem flag)" do
    before do
      allow(command).to receive(:installed_specs).and_return([ build_spec("alpha"), build_spec("beta"), build_spec("empty") ])
    end

    it "returns results from multiple gems and includes a gem field on each result" do
      allow(registry).to receive(:load_gem).with("alpha").and_return(
        build_loaded_gem(name: "alpha", objects: [ build_entry(path: "Alpha::Widget", docstring: "Alpha widget") ])
      )
      allow(registry).to receive(:load_gem).with("beta").and_return(
        build_loaded_gem(name: "beta", objects: [ build_entry(path: "Beta::Widget", docstring: "Beta widget") ])
      )
      allow(registry).to receive(:load_gem).with("empty").and_return(
        build_loaded_gem(name: "empty", doc_source: :none, objects: [])
      )

      status = command.call(query: "Widget", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to match(
        [
          include("path" => "Alpha::Widget", "gem" => "alpha"),
          include("path" => "Beta::Widget", "gem" => "beta")
        ]
      )
    end

    it "caps per-gem contributions at 5 before merging" do
      alpha_objects = Array.new(6) do |index|
        build_entry(path: "Alpha::Widget#{index}", docstring: "Alpha widget #{index}")
      end
      beta_objects = Array.new(2) do |index|
        build_entry(path: "Beta::Widget#{index}", docstring: "Beta widget #{index}")
      end

      allow(registry).to receive(:load_gem).with("alpha").and_return(build_loaded_gem(name: "alpha", objects: alpha_objects))
      allow(registry).to receive(:load_gem).with("beta").and_return(build_loaded_gem(name: "beta", objects: beta_objects))
      allow(registry).to receive(:load_gem).with("empty").and_return(
        build_loaded_gem(name: "empty", doc_source: :none, objects: [])
      )

      status = command.call(query: "Widget", limit: 10, format: "json")

      expect(status).to eq(0)
      payload = JSON.parse(stdout.string)
      expect(payload.count { |result| result.fetch("gem") == "alpha" }).to eq(5)
      expect(payload.count { |result| result.fetch("gem") == "beta" }).to eq(2)
    end

    it "skips gems where doc_source is none" do
      allow(registry).to receive(:load_gem).with("alpha").and_return(
        build_loaded_gem(name: "alpha", objects: [ build_entry(path: "Alpha::Widget", docstring: "Alpha widget") ])
      )
      allow(registry).to receive(:load_gem).with("beta").and_return(
        build_loaded_gem(name: "beta", doc_source: :none, objects: [])
      )
      allow(registry).to receive(:load_gem).with("empty").and_return(
        build_loaded_gem(name: "empty", doc_source: :none, objects: [])
      )

      command.call(query: "Widget", format: "json")

      expect(JSON.parse(stdout.string).map { |result| result.fetch("gem") }).to eq([ "alpha" ])
    end

    it "never raises even if one gem registry is corrupt" do
      allow(registry).to receive(:load_gem).with("alpha").and_raise(GemDocs::RegistryError.new("broken registry"))
      allow(registry).to receive(:load_gem).with("beta").and_return(
        build_loaded_gem(name: "beta", objects: [ build_entry(path: "Beta::Widget", docstring: "Beta widget") ])
      )
      allow(registry).to receive(:load_gem).with("empty").and_return(
        build_loaded_gem(name: "empty", doc_source: :none, objects: [])
      )

      status = command.call(query: "Widget", format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to match(
        [
          include("path" => "Beta::Widget", "gem" => "beta")
        ]
      )
    end
  end
end
