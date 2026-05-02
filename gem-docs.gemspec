# frozen_string_literal: true

require_relative "lib/gem_docs/version"

Gem::Specification.new do |spec|
  spec.name = "gem-docs"
  spec.version = GemDocs::VERSION
  spec.authors = [ "GitHub Copilot CLI" ]
  spec.email = [ "noreply@github.com" ]

  spec.summary = "CLI-first gem documentation lookup for local Ruby projects"
  spec.description = "Provides a CLI-first interface for local gem documentation with an optional MCP server wrapper."
  spec.homepage = "https://github.com/alaexeyshustov/gem-docs-mcp-server"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.chdir(__dir__) do
    Dir["Gemfile", "README.md", "Steepfile", "exe/*", "lib/**/*.rb", "sig/**/*.rbs", "spec/**/*.rb"]
  end
  spec.bindir = "exe"
  spec.executables = [ "gem-docs", "gem-docs-server" ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "dry-cli", "~> 1.0"
  spec.add_dependency "prism", "~> 1.4"
  spec.add_dependency "yard", "~> 0.9"
  spec.add_dependency "zeitwerk", "~> 2.6"
end
