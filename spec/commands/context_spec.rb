# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Commands::Context do
  def build_entry(path:)
    GemDocs::DocRegistry::Entry.new(
      path: path,
      name: path.split(/[:#.]/).last,
      kind: :class,
      visibility: :public,
      docstring: "",
      signature: path,
      source_location: nil,
      superclass: nil,
      doc_source: :yard,
      tags: {},
      aliases: []
    )
  end

  def build_loaded_gem(
    name:,
    version: "1.0.0",
    summary: "Fixture summary",
    doc_source: :yard,
    classes: [],
    entry_points: []
  )
    GemDocs::DocRegistry::LoadedGem.new(
      name: name,
      version: version,
      summary: summary,
      description: summary,
      path: "/tmp/#{name}",
      doc_source: doc_source,
      objects: classes.map { |path| build_entry(path: path) },
      entry_points: entry_points
    )
  end

  let(:stdout) { StringIO.new }
  let(:command) { described_class.new }
  let(:registry) { instance_double(GemDocs::DocRegistry) }
  let(:project_root) { Dir.mktmpdir }

  before do
    allow(command).to receive(:out).and_return(stdout)
    allow(command).to receive(:doc_registry).and_return(registry)
    allow(command).to receive(:project_root).and_return(project_root)
  end

  after do
    FileUtils.remove_entry(project_root)
  end

  it "writes the selected Claude context file with documented gems only" do
    allow(registry).to receive(:load_gem).with("rack", version: nil).and_return(
      build_loaded_gem(
        name: "rack",
        version: "3.1.0",
        summary: "HTTP toolkit",
        classes: [ "Rack::Builder", "Rack::Request" ],
        entry_points: [ "Rack::Builder.new" ]
      )
    )
    allow(registry).to receive(:load_gem).with("undocumented", version: nil).and_return(
      build_loaded_gem(name: "undocumented", doc_source: :none)
    )

    status = command.call(format: "claude", gems: "rack, undocumented", output_dir: "generated")

    expect(status).to eq(0)
    expect(stdout.string).to include("generated/CLAUDE.md")

    output = File.read(File.join(project_root, "generated", "CLAUDE.md"))
    expect(output).to include("# Gem documentation context")
    expect(output).to include("## rack (3.1.0)")
    expect(output).to include("- Entry points: Rack::Builder.new")
    expect(output).not_to include("undocumented")
  end

  it "writes every supported context output when format is all" do
    allow(registry).to receive(:load_gem).with("rack", version: nil).and_return(
      build_loaded_gem(name: "rack", entry_points: [ "Rack::Builder.new" ])
    )

    status = command.call(format: "all", gems: "rack", output_dir: "context")

    expect(status).to eq(0)
    expect(File).to exist(File.join(project_root, "context", "CLAUDE.md"))
    expect(File).to exist(File.join(project_root, "context", ".cursorrules"))
    expect(File).to exist(File.join(project_root, "context", ".windsurfrules"))
    expect(File).to exist(File.join(project_root, "context", ".github", "copilot-instructions.md"))
    expect(File).to exist(File.join(project_root, "context", ".gem-docs-context.json"))
  end

  it "discovers project gems from Gemfile.lock when --gems is omitted" do
    File.write(
      File.join(project_root, "Gemfile.lock"),
      <<~LOCK
        GEM
          specs:
            faraday (2.12.0)
            rack (3.1.0)

        DEPENDENCIES
          faraday
          rack
      LOCK
    )

    allow(registry).to receive(:load_gem).with("faraday", version: nil).and_return(build_loaded_gem(name: "faraday"))
    allow(registry).to receive(:load_gem).with("rack", version: nil).and_return(build_loaded_gem(name: "rack"))

    command.call(format: "claude", output_dir: "context")

    expect(registry).to have_received(:load_gem).with("faraday", version: nil)
    expect(registry).to have_received(:load_gem).with("rack", version: nil)
  end

  it "prefers an explicit gem list over Gemfile.lock discovery" do
    File.write(
      File.join(project_root, "Gemfile.lock"),
      <<~LOCK
        GEM
          specs:
            faraday (2.12.0)

        DEPENDENCIES
          faraday
      LOCK
    )

    allow(registry).to receive(:load_gem).with("rack", version: nil).and_return(build_loaded_gem(name: "rack"))

    command.call(format: "claude", gems: "rack", output_dir: "context")

    expect(registry).to have_received(:load_gem).with("rack", version: nil)
    expect(registry).not_to have_received(:load_gem).with("faraday", version: nil)
  end

  it "raises a configuration error when Gemfile.lock is missing for discovery" do
    expect { command.call(format: "claude", output_dir: "context") }
      .to raise_error(GemDocs::ConfigurationError, /Gemfile\.lock not found/)
  end
end
