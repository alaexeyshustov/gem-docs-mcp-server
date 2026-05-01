# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Zeitwerk loading" do
  let(:repo_root) { Pathname(__dir__).join("..").expand_path }

  def run_ruby(code)
    Open3.capture3("ruby", "-Ilib", "-e", code, chdir: repo_root.to_s)
  end

  it "does not eagerly load command implementations when requiring gem_docs" do
    stdout, stderr, status = run_ruby(<<~RUBY)
      require "gem_docs"

      puts $LOADED_FEATURES.grep(/gem_docs\\/commands\\/list\\.rb$/).empty?
    RUBY

    expect(status).to be_success
    expect(stderr).to eq("")
    expect(stdout).to eq("true\n")
  end

  it "does not eagerly load command implementations when resolving the CLI constant" do
    stdout, stderr, status = run_ruby(<<~RUBY)
      require "gem_docs"
      GemDocs::CLI

      puts $LOADED_FEATURES.grep(/gem_docs\\/commands\\/list\\.rb$/).empty?
    RUBY

    expect(status).to be_success
    expect(stderr).to eq("")
    expect(stdout).to eq("true\n")
  end

  it "autoloads command, formatter, and MCP constants on demand" do
    stdout, stderr, status = run_ruby(<<~RUBY)
      require "gem_docs"

      puts [
        GemDocs::Commands::List.name,
        GemDocs::Formatters::Text.name,
        GemDocs::MCP::Server.name
      ].join(",")
    RUBY

    expect(status).to be_success
    expect(stderr).to eq("")
    expect(stdout).to eq("GemDocs::Commands::List,GemDocs::Formatters::Text,GemDocs::MCP::Server\n")
  end
end
