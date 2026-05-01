# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "gem_docs"

RSpec.describe GemDocs::Config do
  around do |example|
    GemDocs.reset_config_cache!
    example.run
    GemDocs.reset_config_cache!
  end

  it "returns sensible defaults when the config file is missing" do
    Dir.mktmpdir do |tmpdir|
      config = GemDocs.config(root: tmpdir)

      expect(config.to_h).to eq(
        gems: { exclude: [] },
        doc_fallback: { use_rdoc: true, use_source_prism: true },
        output: { color: "auto" }
      )
      expect(config.exclude_gems).to eq([])
      expect(config.use_rdoc?).to be(true)
      expect(config.use_source_prism?).to be(true)
      expect(config.output_color).to eq("auto")
    end
  end

  it "deep merges supported settings from .gem-docs.yml" do
    Dir.mktmpdir do |tmpdir|
      File.write(
        File.join(tmpdir, ".gem-docs.yml"),
        <<~YAML
          gems:
            exclude:
              - bundler
              - rake
          output:
            color: never
        YAML
      )

      config = GemDocs.config(root: tmpdir)

      expect(config.to_h).to eq(
        gems: { exclude: [ "bundler", "rake" ] },
        doc_fallback: { use_rdoc: true, use_source_prism: true },
        output: { color: "never" }
      )
    end
  end
end
