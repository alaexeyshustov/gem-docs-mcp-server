# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "gem_docs"

RSpec.describe GemDocs::Commands::Base do
  around do |example|
    GemDocs.reset_config_cache!
    example.run
    GemDocs.reset_config_cache!
  end

  it "exposes the shared project config helper to commands" do
    Dir.mktmpdir do |tmpdir|
      File.write(
        File.join(tmpdir, ".gem-docs.yml"),
        <<~YAML
          doc_fallback:
            use_rdoc: false
            use_source_prism: false
        YAML
      )

      command = described_class.new

      Dir.chdir(tmpdir) do
        expect(command.send(:config)).to equal(GemDocs.config(root: tmpdir))
        expect(command.send(:config).use_rdoc?).to be(false)
        expect(command.send(:config).use_source_prism?).to be(false)
      end
    end
  end
end
