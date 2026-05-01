# frozen_string_literal: true

require "spec_helper"
require "gem_docs"

RSpec.describe "bootstrap structure" do
  let(:repo_root) { Pathname(__dir__).join("..").expand_path }

  it "creates the expected CLI-first filesystem layout" do
    expected_paths = %w[
      exe/gem-docs
      exe/gem-docs-server
      lib/gem_docs.rb
      lib/gem_docs/cli.rb
      lib/gem_docs/version.rb
      lib/gem_docs/doc_registry.rb
      lib/gem_docs/commands.rb
      lib/gem_docs/commands/list.rb
      lib/gem_docs/commands/summary.rb
      lib/gem_docs/commands/classes.rb
      lib/gem_docs/commands/lookup.rb
      lib/gem_docs/commands/search.rb
      lib/gem_docs/commands/context.rb
      lib/gem_docs/commands/server.rb
      lib/gem_docs/formatters.rb
      lib/gem_docs/formatters/text.rb
      lib/gem_docs/formatters/json.rb
      lib/gem_docs/mcp.rb
      lib/gem_docs/mcp/server.rb
    ]

    expected_paths.each do |relative_path|
      expect(repo_root.join(relative_path)).to exist
    end
  end

  it "marks both executables as runnable" do
    expect(repo_root.join("exe/gem-docs")).to be_executable
    expect(repo_root.join("exe/gem-docs-server")).to be_executable
  end

  it "declares the runtime, development, and optional dependencies from the PRD" do
    spec = Gem::Specification.load(repo_root.join("gem-docs.gemspec").to_s)
    gemfile = repo_root.join("Gemfile").read

    expect(spec.required_ruby_version).to eq(Gem::Requirement.new(">= 3.2"))
    expect(spec.executables).to contain_exactly("gem-docs", "gem-docs-server")
    expect(spec.version.to_s).to eq(GemDocs::VERSION)
    expect(spec.runtime_dependencies.map(&:name)).to contain_exactly("dry-cli", "prism", "yard", "zeitwerk")

    expect(gemfile).to include('group :mcp do')
    expect(gemfile).to include('gem "fast-mcp", require: false')
    expect(gemfile).to include('gem "rspec", "~> 3.13"')
    expect(gemfile).to include('gem "rubocop-rails-omakase", require: false')
  end
end
