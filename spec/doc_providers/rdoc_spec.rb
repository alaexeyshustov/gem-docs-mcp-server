# frozen_string_literal: true

require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::DocProviders::Rdoc do
  describe "#available?" do
    it "returns false when ri cannot be executed" do
      with_source_fixture_gem("ri_missing", source: "module RiMissing; end\n") do |spec|
        FileUtils.mkdir_p(spec.doc_dir)
        provider = described_class.new(
          shell_runner: lambda do |_command|
            raise Errno::ENOENT, "ri"
          end,
          loaded_gem_builder: ->(*) { raise "unused" }
        )

        expect(provider.available?(spec)).to eq(false)
      end
    end
  end

  describe "#load" do
    it "loads the ri index and lazily hydrates objects on demand" do
      stub_fixture_gem("rdoc_only", registry_class: GemDocs::DocRegistry) do |spec|
        commands = []
        provider = described_class.new(
          shell_runner: lambda do |command|
            commands << command

            case command.last
            when "-l"
              { stdout: "RdocOnly::Widget\nRdocOnly::Widget#call\n", stderr: "", success: true }
            when "RdocOnly::Widget#call"
              { stdout: "RdocOnly::Widget#call\n\nCalls through ri.\n", stderr: "", success: true }
            else
              { stdout: "class RdocOnly::Widget\n\nThe primary RDoc class.\n", stderr: "", success: true }
            end
          end,
          loaded_gem_builder: lambda do |resolved_spec, objects, doc_source, dynamic_lookup: nil, lazy_paths: []|
            GemDocs::DocRegistry::LoadedGem.new(
              name: resolved_spec.name,
              version: resolved_spec.version.to_s,
              summary: resolved_spec.summary,
              path: resolved_spec.full_gem_path,
              doc_source: doc_source,
              objects: objects,
              dynamic_lookup: dynamic_lookup,
              lazy_paths: lazy_paths
            )
          end
        )

        loaded_gem = provider.load(spec)

        expect(loaded_gem.doc_source).to eq(:rdoc)
        expect(loaded_gem.find("RdocOnly::Widget#call")).to have_attributes(
          path: "RdocOnly::Widget#call",
          doc_source: :rdoc,
          docstring: "Calls through ri."
        )
        expect(commands.map(&:last)).to eq([ "-l", "RdocOnly::Widget#call" ])
      end
    end
  end

  describe "#lookup" do
    it "passes lookup targets after the end-of-options marker" do
      stub_fixture_gem("rdoc_only", registry_class: GemDocs::DocRegistry) do |spec|
        commands = []
        provider = described_class.new(
          shell_runner: lambda do |command|
            commands << command
            { stdout: "RdocOnly::--\n\nFlag-like target.\n", stderr: "", success: true }
          end,
          loaded_gem_builder: ->(*) { raise "unused" }
        )

        provider.lookup(spec, "RdocOnly::--")

        expect(commands).to eq([
          [ "ri", "--no-pager", "--no-standard-docs", "-d", spec.doc_dir, "--", "RdocOnly::--" ]
        ])
      end
    end
  end
end
