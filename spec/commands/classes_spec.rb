# frozen_string_literal: true

require "json"
require "stringio"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Commands::Classes do
  def build_entry(path:, kind: :class, visibility: :public, docstring: "", superclass: nil)
    GemDocs::DocRegistry::Entry.new(
      path: path,
      name: path.split(/[:#.]/).last,
      kind: kind,
      visibility: visibility,
      docstring: docstring,
      signature: path,
      source_location: nil,
      superclass: superclass,
      doc_source: :yard
    )
  end

  def build_loaded_gem(name:, version: "1.0.0", summary: "", objects:)
    GemDocs::DocRegistry::LoadedGem.new(
      name: name,
      version: version,
      summary: summary,
      path: "/tmp/#{name}",
      doc_source: :yard,
      objects: objects
    )
  end

  let(:stdout) { StringIO.new }
  let(:command) { described_class.new }
  let(:registry) { instance_double(GemDocs::DocRegistry) }

  before do
    allow(command).to receive(:out).and_return(stdout)
    allow(command).to receive(:doc_registry).and_return(registry)
  end

  it "renders classes as JSON with type, superclass, summary, and method count" do
    allow(registry).to receive(:load_gem).with("example", version: nil).and_return(
      build_loaded_gem(
        name: "example",
        objects: [
          build_entry(path: "Example::Widget", docstring: "Widget summary.\n\nMore details.", superclass: "BaseWidget"),
          build_entry(path: "Example::Widget#call", kind: :instance_method),
          build_entry(path: "Example::Widget.build", kind: :class_method)
        ]
      )
    )

    status = command.call(gem_name: "example", format: "json")

    expect(status).to eq(0)
    expect(JSON.parse(stdout.string)).to eq(
      [
        {
          "name" => "Example::Widget",
          "type" => "class",
          "superclass" => "BaseWidget",
          "summary" => "Widget summary.",
          "method_count" => 2
        }
      ]
    )
  end

  it "sorts results alphabetically and excludes private or anonymous entries" do
    allow(registry).to receive(:load_gem).with("example", version: nil).and_return(
      build_loaded_gem(
        name: "example",
        objects: [
          build_entry(path: "Example::Zulu", docstring: "", superclass: nil),
          build_entry(path: "Example::Zulu#call", kind: :instance_method),
          build_entry(path: "Example::Alpha", kind: :module, docstring: "Alpha summary"),
          build_entry(path: "Example::Alpha.configure", kind: :class_method),
          build_entry(path: "Example::Hidden", visibility: :private),
          build_entry(path: "#<Class:0x1234>"),
          build_entry(path: "#<Class:0x1234>#call", kind: :instance_method)
        ]
      )
    )

    command.call(gem_name: "example", format: "json")

    expect(JSON.parse(stdout.string)).to eq(
      [
        {
          "name" => "Example::Alpha",
          "type" => "module",
          "summary" => "Alpha summary",
          "method_count" => 1
        },
        {
          "name" => "Example::Zulu",
          "type" => "class",
          "superclass" => "Object",
          "summary" => "",
          "method_count" => 1
        }
      ]
    )
  end

  it "renders readable text rows for scanning a gem surface area" do
    allow(registry).to receive(:load_gem).with("example", version: nil).and_return(
      build_loaded_gem(
        name: "example",
        objects: [
          build_entry(path: "Example::Alpha", kind: :module, docstring: "Alpha summary"),
          build_entry(path: "Example::Alpha.configure", kind: :class_method),
          build_entry(path: "Example::Widget", docstring: "Widget summary", superclass: "BaseWidget"),
          build_entry(path: "Example::Widget#call", kind: :instance_method),
          build_entry(path: "Example::Widget.build", kind: :class_method)
        ]
      )
    )

    status = command.call(gem_name: "example", format: "text")

    expect(status).to eq(0)
    expect(stdout.string.lines).to eq(
      [
        "Example::Alpha   module  (1 method)   Alpha summary\n",
        "Example::Widget  class   (2 methods)  Widget summary\n"
      ]
    )
  end
end
