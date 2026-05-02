# frozen_string_literal: true

require "spec_helper"

RSpec.describe "typing setup" do
  let(:repo_root) { Pathname(__dir__).join("..").expand_path }

  it "declares steep and rbs as development dependencies" do
    gemfile = repo_root.join("Gemfile").read

    expect(gemfile).to include('gem "rbs"')
    expect(gemfile).to include('gem "steep"')
  end

  it "ships project signatures and a steep configuration" do
    spec = Gem::Specification.load(repo_root.join("gem-docs.gemspec").to_s)
    steepfile = repo_root.join("Steepfile")

    expect(steepfile).to exist
    expect(steepfile.read).to include("target :lib")
    expect(spec.files).to include("Steepfile")
    expect(spec.files).to include("sig/gem_docs.rbs")
  end
end
