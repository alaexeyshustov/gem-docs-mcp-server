# frozen_string_literal: true

require "tmpdir"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::Compression::Pipeline do
  it "reads cached source artifacts and stores compressed knowledge with source linkage" do
    with_yard_fixture_gem(name: "compression_fixture", source: <<~RUBY) do
      module CompressionFixture
        class Client
          # Retries idempotent requests with exponential backoff.
          #
          # The middleware only retries safe failures and respects `Retry-After`.
          def call
          end
        end
      end
    RUBY
      Dir.mktmpdir do |tmpdir|
        cache = GemDocs::ArtifactCache.new(path: File.join(tmpdir, "artifacts.sqlite3"))
        registry = GemDocs::DocRegistry.new(cache: cache)

        registry.load_gem("compression_fixture")

        pipeline = described_class.new(
          cache: cache,
          doc_registry: registry,
          compressor: lambda do |gem:, source_artifact:, prompt:, schema:|
            expect(gem).to include(name: "compression_fixture", version: "0.1.0")
            expect(prompt).to include("non-obvious")
            expect(schema.fetch("required")).to include("status", "insights")

            {
              "status" => "ready",
              "insights" => [
                {
                  "title" => "Insight for #{source_artifact.fetch(:lookup_target)}",
                  "detail" => "Backoff follows Retry-After instead of using only the local schedule.",
                  "categories" => [ "behavior", "edge_case" ],
                  "version_scope" => "0.1.0"
                }
              ]
            }
          end
        )

        result = pipeline.compress_gem("compression_fixture")
        payload = cache.fetch_artifact(
          gem_name: "compression_fixture",
          gem_version: "0.1.0",
          lookup_target: "CompressionFixture::Client#call",
          artifact_kind: :compressed,
          invalidation_key: registry.artifact_invalidation_key_for("compression_fixture")
        )

        expect(result).to eq(gem_name: "compression_fixture", gem_version: "0.1.0", compressed_count: 3)
        expect(payload).to include(
          "status" => "ready",
          "insights" => [
            include(
              "title" => "Insight for CompressionFixture::Client#call",
              "detail" => "Backoff follows Retry-After instead of using only the local schedule."
            )
          ],
          "prompt_version" => GemDocs::Compression::Pipeline::PROMPT_VERSION
        )
        expect(payload.fetch("source_artifact")).to include(
          "lookup_target" => "CompressionFixture::Client#call",
          "artifact_kind" => "source",
          "artifact_version" => GemDocs::ArtifactCache::ARTIFACT_VERSIONS.fetch(:source)
        )
        expect(payload.fetch("source_artifact").fetch("payload_digest")).not_to be_empty
      end
    end
  end
end
