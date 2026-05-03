# frozen_string_literal: true

require "json"
require "stringio"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Commands::List do
  def build_spec(name:, version:, summary:)
    instance_double(
      Gem::Specification,
      name: name,
      version: Gem::Version.new(version),
      summary: summary
    )
  end

  let(:stdout) { StringIO.new }
  let(:command) { described_class.new }
  let(:registry) { instance_double(GemDocs::DocRegistry) }
  let(:config) { instance_double(GemDocs::Config, exclude_gems: []) }

  before do
    allow(command).to receive(:out).and_return(stdout)
    allow(command).to receive(:config).and_return(config)
    allow(command).to receive(:doc_registry).and_return(registry)
  end

  describe "--format json" do
    it "outputs valid JSON to stdout" do
      allow(command).to receive(:installed_specs).and_return(
        [
          build_spec(name: "faraday", version: "2.12.0", summary: "HTTP/REST API client library.")
        ]
      )
      allow(registry).to receive(:load_gem).with("faraday").and_return(
        instance_double(GemDocs::DocRegistry::LoadedGem, doc_source: :yard)
      )

      status = command.call(format: "json")

      expect(status).to eq(0)
      expect(JSON.parse(stdout.string)).to eq(
        [
          {
            "name" => "faraday",
            "version" => "2.12.0",
            "doc_source" => "yard",
            "summary" => "HTTP/REST API client library."
          }
        ]
      )
    end

    it "includes the supported documentation sources for each gem" do
      allow(command).to receive(:installed_specs).and_return(
        [
          build_spec(name: "broken-gem", version: "0.0.1", summary: ""),
          build_spec(name: "faraday", version: "2.12.0", summary: "HTTP/REST API client library."),
          build_spec(name: "rake", version: "13.2.1", summary: "Ruby build tool."),
          build_spec(name: "source-only", version: "0.1.0", summary: "Fallback docs")
        ]
      )
      allow(registry).to receive(:load_gem).with("faraday").and_return(
        instance_double(GemDocs::DocRegistry::LoadedGem, doc_source: :yard)
      )
      allow(registry).to receive(:load_gem).with("rake").and_return(
        instance_double(GemDocs::DocRegistry::LoadedGem, doc_source: :rdoc)
      )
      allow(registry).to receive(:load_gem).with("source-only").and_return(
        instance_double(GemDocs::DocRegistry::LoadedGem, doc_source: :source_only)
      )
      allow(registry).to receive(:load_gem).with("broken-gem").and_raise(GemDocs::RegistryError.new("boom"))

      command.call(format: "json")

      expect(JSON.parse(stdout.string)).to eq(
        [
          { "name" => "broken-gem", "version" => "0.0.1", "doc_source" => "none" },
          {
            "name" => "faraday",
            "version" => "2.12.0",
            "doc_source" => "yard",
            "summary" => "HTTP/REST API client library."
          },
          {
            "name" => "rake",
            "version" => "13.2.1",
            "doc_source" => "rdoc",
            "summary" => "Ruby build tool."
          },
          {
            "name" => "source-only",
            "version" => "0.1.0",
            "doc_source" => "source_only",
            "summary" => "Fallback docs"
          }
        ]
      )
    end

    it "excludes gems listed in configuration" do
      allow(command).to receive(:installed_specs).and_return(
        [
          build_spec(name: "bundler", version: "2.5.9", summary: "Bundler"),
          build_spec(name: "faraday", version: "2.12.0", summary: "HTTP/REST API client library.")
        ]
      )
      allow(command).to receive(:config).and_return(instance_double(GemDocs::Config, exclude_gems: [ "bundler" ]))
      allow(registry).to receive(:load_gem).with("faraday").and_return(
        instance_double(GemDocs::DocRegistry::LoadedGem, doc_source: :yard)
      )

      command.call(format: "json")

      expect(JSON.parse(stdout.string)).to eq(
        [
          {
            "name" => "faraday",
            "version" => "2.12.0",
            "doc_source" => "yard",
            "summary" => "HTTP/REST API client library."
          }
        ]
      )
    end
  end

  describe "--format text" do
    it "outputs a human-readable aligned table" do
      allow(command).to receive(:installed_specs).and_return(
        [
          build_spec(name: "faraday", version: "2.12.0", summary: "HTTP/REST API client library."),
          build_spec(name: "obscure-gem", version: "0.1.0", summary: "")
        ]
      )
      allow(registry).to receive(:load_gem).with("faraday").and_return(
        instance_double(GemDocs::DocRegistry::LoadedGem, doc_source: :yard)
      )
      allow(registry).to receive(:load_gem).with("obscure-gem").and_return(
        instance_double(GemDocs::DocRegistry::LoadedGem, doc_source: :source_only)
      )

      status = command.call(format: "text")

      expect(status).to eq(0)
      expect(stdout.string.lines).to eq(
        [
          "NAME         VERSION  DOC SOURCE   SUMMARY\n",
          "faraday      2.12.0   yard         HTTP/REST API client library.\n",
          "obscure-gem  0.1.0    source_only\n"
        ]
      )
    end
  end
end
