# frozen_string_literal: true

require "json"
require "stringio"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Commands::Summary do
  def build_entry(path:, kind: :class)
    GemDocs::DocRegistry::Entry.new(
      path: path,
      name: path.split(/[:#.]/).last,
      kind: kind,
      visibility: :public,
      docstring: "",
      signature: path,
      source_location: nil,
      superclass: nil,
      doc_source: :yard
    )
  end

  def build_loaded_gem(
    name:,
    version:,
    summary:,
    description: summary,
    homepage: nil,
    license: nil,
    doc_source:,
    entry_points: [],
    objects:
  )
    GemDocs::DocRegistry::LoadedGem.new(
      name: name,
      version: version,
      summary: summary,
      description: description,
      homepage: homepage,
      license: license,
      path: "/tmp/#{name}",
      doc_source: doc_source,
      objects: objects,
      entry_points: entry_points
    )
  end

  let(:stdout) { StringIO.new }
  let(:command) { described_class.new }
  let(:registry) { instance_double(GemDocs::DocRegistry) }

  before do
    allow(command).to receive(:out).and_return(stdout)
    allow(command).to receive(:doc_registry).and_return(registry)
  end

  it "outputs the documented JSON summary for a requested gem version" do
    allow(registry).to receive(:load_gem).with("faraday", version: "2.12.0").and_return(
      build_loaded_gem(
        name: "faraday",
        version: "2.12.0",
        summary: "HTTP/REST API client library for Ruby.",
        homepage: "https://github.com/lostisland/faraday",
        license: "MIT",
        doc_source: :yard,
        entry_points: [ "Faraday.new", "Faraday::Connection#get" ],
        objects: [
          build_entry(path: "Faraday"),
          build_entry(path: "Faraday::Connection"),
          build_entry(path: "Faraday::Response")
        ]
      )
    )

    status = command.call(gem_name: "faraday", version: "2.12.0", format: "json")

    expect(status).to eq(0)
    expect(JSON.parse(stdout.string)).to eq(
      "name" => "faraday",
      "version" => "2.12.0",
      "description" => "HTTP/REST API client library for Ruby.",
      "homepage" => "https://github.com/lostisland/faraday",
      "license" => "MIT",
      "doc_source" => "yard",
      "classes" => [ "Faraday", "Faraday::Connection", "Faraday::Response" ],
      "entry_points" => [ "Faraday.new", "Faraday::Connection#get" ]
    )
  end

  it "renders a readable text summary with entry points" do
    allow(registry).to receive(:load_gem).with("faraday", version: nil).and_return(
      build_loaded_gem(
        name: "faraday",
        version: "2.12.0",
        summary: "HTTP/REST API client library for Ruby.",
        homepage: "https://github.com/lostisland/faraday",
        license: "MIT",
        doc_source: :yard,
        entry_points: [ "Faraday.new", "Faraday::Connection#get" ],
        objects: [
          build_entry(path: "Faraday"),
          build_entry(path: "Faraday::Connection")
        ]
      )
    )

    status = command.call(gem_name: "faraday", format: "text")

    expect(status).to eq(0)
    expect(stdout.string).to eq(
      "faraday 2.12.0 [yard]\n" \
      "HTTP/REST API client library for Ruby.\n" \
      "https://github.com/lostisland/faraday\n" \
      "License: MIT\n" \
      "Classes: Faraday, Faraday::Connection\n" \
      "Entry points:\n" \
      "  Faraday.new\n" \
      "  Faraday::Connection#get\n"
    )
  end

  it "preserves empty entry points for source-only gems in JSON output" do
    allow(registry).to receive(:load_gem).with("source-only", version: nil).and_return(
      build_loaded_gem(
        name: "source-only",
        version: "0.1.0",
        summary: "Fallback docs",
        doc_source: :source_only,
        objects: [ build_entry(path: "SourceOnly::Widget") ]
      )
    )

    command.call(gem_name: "source-only", format: "json")

    expect(JSON.parse(stdout.string)).to include(
      "name" => "source-only",
      "doc_source" => "source_only",
      "classes" => [ "SourceOnly::Widget" ],
      "entry_points" => []
    )
  end
end
