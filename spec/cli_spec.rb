# frozen_string_literal: true

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
end
