# frozen_string_literal: true

require "json"
require "stringio"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::CLI do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  it "renders dry-cli help for the top-level help flag" do
    status = described_class.start([ "--help" ], out: stdout, err: stderr)

    expect(status).to eq(0)
    expect(stderr.string).to eq("")
    expect(stdout.string).to include("Commands:")
    expect(stdout.string).to include("list")
    expect(stdout.string).to include("Show installed gems")
  end

  it "renders dry-cli command help for subcommands" do
    status = described_class.start([ "list", "--help" ], out: stdout, err: stderr)

    expect(status).to eq(0)
    expect(stderr.string).to eq("")
    expect(stdout.string).to include("Command:")
    expect(stdout.string).to include("Description:")
    expect(stdout.string).to include("Show installed gems")
  end

  it "returns dry-cli usage for unknown commands" do
    status = described_class.start([ "unknown" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(stderr.string).to include("Commands:")
    expect(stderr.string).to include("list")
  end

  it "dispatches registered commands through dry-cli" do
    status = described_class.start([ "search" ], out: stdout, err: stderr)

    expect(status).to eq(0)
    expect(stderr.string).to eq("")
    expect(stdout.string).to eq("search is not implemented yet.\n")
  end

  it "renders structured JSON for handled command errors" do
    stub_const("GemDocs::Commands::List", Class.new(GemDocs::Commands::Base) do
      desc "Show installed gems"

      def call(**)
        raise GemDocs::GemNotFound.new("missing-gem")
      end
    end)

    status = described_class.start([ "list", "--format", "json" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(JSON.parse(stderr.string)).to eq(
      "error" => "not_found",
      "message" => "Gem 'missing-gem' is not installed"
    )
  end

  it "renders unavailable errors with the shared JSON envelope" do
    stub_const("GemDocs::Commands::Lookup", Class.new(GemDocs::Commands::Base) do
      desc "Look up a constant or method"

      def call(**)
        raise GemDocs::DocUnavailable.new("missing-gem")
      end
    end)

    status = described_class.start([ "lookup", "--format", "json" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(JSON.parse(stderr.string)).to eq(
      "error" => "unavailable",
      "message" => "Documentation is unavailable for 'missing-gem'"
    )
  end

  it "renders structured JSON errors for summary lookup failures" do
    stub_const("GemDocs::Commands::Summary", Class.new(GemDocs::Commands::Base) do
      desc "Summarize a gem"

      def call(**)
        raise GemDocs::GemNotFound.new("missing-gem")
      end
    end)

    status = described_class.start([ "summary", "missing-gem", "--format", "json" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(JSON.parse(stderr.string)).to eq(
      "error" => "not_found",
      "message" => "Gem 'missing-gem' is not installed"
    )
  end

  it "renders structured JSON errors for classes lookup failures" do
    stub_const("GemDocs::Commands::Classes", Class.new(GemDocs::Commands::Base) do
      desc "List documented classes and modules"
      argument :gem_name, type: :string

      def call(**)
        raise GemDocs::GemNotFound.new("missing-gem")
      end
    end)

    status = described_class.start([ "classes", "missing-gem", "--format", "json" ], out: stdout, err: stderr)

    expect(status).to eq(1)
    expect(stdout.string).to eq("")
    expect(JSON.parse(stderr.string)).to eq(
      "error" => "not_found",
      "message" => "Gem 'missing-gem' is not installed"
    )
  end

  it "accepts --version for the summary command" do
    registry = instance_double(
      GemDocs::DocRegistry,
      load_gem: GemDocs::DocRegistry::LoadedGem.new(
        name: "faraday",
        version: "2.12.0",
        summary: "HTTP client",
        description: "HTTP client",
        path: "/tmp/faraday",
        doc_source: :yard,
        objects: []
      )
    )
    allow(GemDocs::DocRegistry).to receive(:new).and_return(registry)

    status = described_class.start([ "summary", "faraday", "--version", "2.12.0" ], out: stdout, err: stderr)

    expect(status).to eq(0)
    expect(stderr.string).to eq("")
    expect(registry).to have_received(:load_gem).with("faraday", version: "2.12.0")
  end
end
