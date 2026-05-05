# frozen_string_literal: true

require "tmpdir"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::ArtifactCache do
  it "keeps source and compressed artifacts separate and falls back to source artifacts" do
    Dir.mktmpdir do |tmpdir|
      cache = described_class.new(path: File.join(tmpdir, "artifacts.sqlite3"))

      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :source,
        payload: { "docstring" => "Full source docs" },
        invalidation_key: "digest-v1"
      )

      expect(cache.fetch_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :compressed,
        invalidation_key: "digest-v1"
      )).to be_nil

      expect(cache.fetch_with_fallback(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        invalidation_key: "digest-v1"
      )).to eq(
        {
          kind: :source,
          payload: { "docstring" => "Full source docs" }
        }
      )

      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :compressed,
        payload: { "summary" => "Short summary" },
        invalidation_key: "digest-v1"
      )

      expect(cache.fetch_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :source,
        invalidation_key: "digest-v1"
      )).to eq({ "docstring" => "Full source docs" })
      expect(cache.fetch_with_fallback(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        invalidation_key: "digest-v1"
      )).to eq(
        {
          kind: :compressed,
          payload: { "summary" => "Short summary" }
        }
      )
    end
  end

  it "separates persisted artifacts by gem version" do
    Dir.mktmpdir do |tmpdir|
      cache = described_class.new(path: File.join(tmpdir, "artifacts.sqlite3"))

      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget",
        artifact_kind: :source,
        payload: { "version" => "1.0.0" },
        invalidation_key: "digest-v1"
      )
      cache.write_artifact(
        gem_name: "demo",
        gem_version: "2.0.0",
        lookup_target: "Demo::Widget",
        artifact_kind: :source,
        payload: { "version" => "2.0.0" },
        invalidation_key: "digest-v2"
      )

      expect(cache.fetch_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget",
        artifact_kind: :source,
        invalidation_key: "digest-v1"
      )).to eq({ "version" => "1.0.0" })
      expect(cache.fetch_artifact(
        gem_name: "demo",
        gem_version: "2.0.0",
        lookup_target: "Demo::Widget",
        artifact_kind: :source,
        invalidation_key: "digest-v2"
      )).to eq({ "version" => "2.0.0" })
    end
  end
end
