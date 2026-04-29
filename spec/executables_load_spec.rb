# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

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

  it "routes the CLI server command through the MCP server loader" do
    stdout, stderr, status = run_command("ruby", "-Ilib", "exe/gem-docs", "server")

    expect(status).to be_success
    expect(stderr).to eq("")
    expect(stdout).to include("gem-docs-server placeholder loaded")
  end

  it "reports fast-mcp load failures from the CLI server command without a stack trace" do
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "fast_mcp.rb"), "raise RuntimeError, 'simulated fast_mcp load failure'\n")

      stdout, stderr, status = run_command("ruby", "-I#{tmpdir}", "-Ilib", "exe/gem-docs", "server")

      expect(status.exitstatus).to eq(1)
      expect(stdout).to eq("")
      expect(stderr).to eq("gem-docs-server failed to load fast-mcp: RuntimeError: simulated fast_mcp load failure\n")
    end
  end

  it "keeps fast-mcp isolated from the default CLI load path" do
    stdout, stderr, status = run_command(
      "ruby",
      "-Ilib",
      "-e",
      "require 'gem_docs'; puts [$LOADED_FEATURES.grep(/fast_mcp/).empty?, $LOADED_FEATURES.grep(/gem_docs\\/mcp\\/server/).empty?].join(':')"
    )

    expect(status).to be_success
    expect(stderr).to eq("")
    expect(stdout).to eq("true:true\n")
  end
end
