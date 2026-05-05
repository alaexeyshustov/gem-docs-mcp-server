# frozen_string_literal: true

require "tmpdir"
require "spec_helper"
require "gem_docs"

RSpec.describe GemDocs::ArtifactCache do
  it "configures a busy timeout for SQLite connections" do
    Dir.mktmpdir do |tmpdir|
      cache = described_class.new(path: File.join(tmpdir, "artifacts.sqlite3"))
      database = instance_double(SQLite3::Database)

      allow(SQLite3::Database).to receive(:new).and_return(database)
      allow(database).to receive(:execute_batch)
      allow(database).to receive(:get_first_row).and_return([ described_class::SCHEMA_VERSION.to_s ])
      allow(database).to receive(:execute)
      allow(database).to receive(:close)

      expect(database).to receive(:busy_timeout=).with(described_class::BUSY_TIMEOUT_MS)

      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :source,
        payload: { "docstring" => "Full source docs" },
        invalidation_key: "digest-v1"
      )
    end
  end

  it "retries writes when SQLite reports the database is locked" do
    Dir.mktmpdir do |tmpdir|
      cache = described_class.new(path: File.join(tmpdir, "artifacts.sqlite3"))
      database = instance_double(SQLite3::Database)

      allow(SQLite3::Database).to receive(:new).and_return(database)
      allow(database).to receive(:busy_timeout=)
      allow(database).to receive(:execute_batch)
      allow(database).to receive(:get_first_row).and_return([ described_class::SCHEMA_VERSION.to_s ])
      allow(database).to receive(:close)
      allow(cache).to receive(:sleep)

      attempts = 0
      allow(database).to receive(:execute) do
        attempts += 1
        raise SQLite3::BusyException, "database is locked" if attempts == 1
      end

      expect(cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :source,
        payload: { "docstring" => "Full source docs" },
        invalidation_key: "digest-v1"
      )).to be(true)
      expect(attempts).to eq(2)
    end
  end

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

  it "falls back to source artifacts when compressed knowledge is marked insufficient" do
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
      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :compressed,
        payload: {
          "status" => "insufficient",
          "reason" => "The raw documentation is already obvious."
        },
        invalidation_key: "digest-v1"
      )

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
    end
  end

  it "lists source artifacts for offline compression by gem version and invalidation key" do
    Dir.mktmpdir do |tmpdir|
      cache = described_class.new(path: File.join(tmpdir, "artifacts.sqlite3"))

      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget",
        artifact_kind: :source,
        payload: { "path" => "Demo::Widget", "docstring" => "Widget docs" },
        invalidation_key: "digest-v1"
      )
      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :source,
        payload: { "path" => "Demo::Widget#call", "docstring" => "Stale docs" },
        invalidation_key: "digest-v0"
      )
      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: "Demo::Widget#call",
        artifact_kind: :source,
        payload: { "path" => "Demo::Widget#call", "docstring" => "Call docs" },
        invalidation_key: "digest-v1"
      )
      cache.write_artifact(
        gem_name: "demo",
        gem_version: "1.0.0",
        lookup_target: described_class::GEM_LOOKUP_TARGET,
        artifact_kind: :source,
        payload: { "name" => "demo" },
        invalidation_key: "digest-v1"
      )

      expect(cache.source_artifacts(
        gem_name: "demo",
        gem_version: "1.0.0",
        invalidation_key: "digest-v1"
      )).to eq(
        [
          {
            lookup_target: "Demo::Widget",
            artifact_version: described_class::ARTIFACT_VERSIONS.fetch(:source),
            invalidation_key: "digest-v1",
            payload: { "path" => "Demo::Widget", "docstring" => "Widget docs" },
            payload_digest: Digest::SHA256.hexdigest(JSON.generate({ "path" => "Demo::Widget", "docstring" => "Widget docs" }))
          },
          {
            lookup_target: "Demo::Widget#call",
            artifact_version: described_class::ARTIFACT_VERSIONS.fetch(:source),
            invalidation_key: "digest-v1",
            payload: { "path" => "Demo::Widget#call", "docstring" => "Call docs" },
            payload_digest: Digest::SHA256.hexdigest(JSON.generate({ "path" => "Demo::Widget#call", "docstring" => "Call docs" }))
          }
        ]
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
