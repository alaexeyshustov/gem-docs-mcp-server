# frozen_string_literal: true

require "spec_helper"

RSpec.describe "executables" do
  let(:repo_root) { Pathname(__dir__).join("..").expand_path }

  def run_command(*command)
    Open3.capture3(*command, chdir: repo_root.to_s)
  end

  it "loads the CLI executable without missing file errors" do
    stdout, stderr, status = run_command("ruby", "-Ilib", "exe/gem-docs")

    expect(status).to be_success
    expect("#{stdout}\n#{stderr}").to include("gem-docs")
  end

  it "loads the server executable and reports the optional fast-mcp dependency cleanly" do
    stdout, stderr, status = run_command("ruby", "-Ilib", "exe/gem-docs-server")

    expect(status).to be_success
    expect("#{stdout}\n#{stderr}").to include("gem-docs-server")
  end

  it "keeps fast-mcp isolated from the default CLI load path" do
    stdout, stderr, status = run_command("ruby", "-Ilib", "-e", "require 'gem_docs'; puts $LOADED_FEATURES.grep(/fast_mcp/).empty?")

    expect(status).to be_success
    expect(stderr).to eq("")
    expect(stdout).to eq("true\n")
  end
end
