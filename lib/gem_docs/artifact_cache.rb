# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "sqlite3"

module GemDocs
  class ArtifactCache
    SCHEMA_VERSION = 1
    BUSY_TIMEOUT_MS = 5_000
    MAX_BUSY_RETRIES = 2
    BUSY_RETRY_DELAY = 0.05
    GEM_LOOKUP_TARGET = "__gem__"
    ARTIFACT_VERSIONS = {
      source: 1,
      compressed: 1
    }.freeze

    def self.default(root: Dir.pwd)
      new(path: File.join(root, ".gem-docs", "cache.sqlite3"))
    end

    def initialize(path:)
      @path = path
    end

    def fetch_loaded_gem(gem_name:, gem_version:, invalidation_key:)
      payload = fetch_artifact(
        gem_name: gem_name,
        gem_version: gem_version,
        lookup_target: GEM_LOOKUP_TARGET,
        artifact_kind: :source,
        invalidation_key: invalidation_key
      )
      return unless payload

      build_loaded_gem(payload)
    end

    def write_loaded_gem(loaded_gem, invalidation_key:)
      write_artifact(
        gem_name: loaded_gem.name,
        gem_version: loaded_gem.version,
        lookup_target: GEM_LOOKUP_TARGET,
        artifact_kind: :source,
        payload: serialize_loaded_gem(loaded_gem),
        invalidation_key: invalidation_key
      )
    end

    def fetch_artifact(gem_name:, gem_version:, lookup_target:, artifact_kind:, invalidation_key:, artifact_version: nil)
      with_database do |database|
        row = database.get_first_row(
          <<~SQL,
            SELECT payload
            FROM documentation_artifacts
            WHERE gem_name = ?
              AND gem_version = ?
              AND lookup_target = ?
              AND artifact_kind = ?
              AND invalidation_key = ?
              AND artifact_version = ?
          SQL
          gem_name,
          gem_version,
          lookup_target,
          artifact_kind.to_s,
          invalidation_key,
          artifact_version || default_artifact_version(artifact_kind)
        )

        row ? JSON.parse(row[0]) : nil
      end
    end

    def fetch_with_fallback(gem_name:, gem_version:, lookup_target:, invalidation_key:)
      compressed = fetch_artifact(
        gem_name: gem_name,
        gem_version: gem_version,
        lookup_target: lookup_target,
        artifact_kind: :compressed,
        invalidation_key: invalidation_key
      )
      return { kind: :compressed, payload: compressed } if compressed_usable?(compressed)

      source = fetch_artifact(
        gem_name: gem_name,
        gem_version: gem_version,
        lookup_target: lookup_target,
        artifact_kind: :source,
        invalidation_key: invalidation_key
      )
      return { kind: :source, payload: source } if source

      nil
    end

    def source_artifacts(gem_name:, gem_version:, invalidation_key:)
      with_database do |database|
        database.execute(
          <<~SQL,
            SELECT lookup_target, artifact_version, invalidation_key, payload
            FROM documentation_artifacts
            WHERE gem_name = ?
              AND gem_version = ?
              AND artifact_kind = 'source'
              AND invalidation_key = ?
              AND lookup_target != ?
            ORDER BY lookup_target ASC
          SQL
          gem_name,
          gem_version,
          invalidation_key,
          GEM_LOOKUP_TARGET
        ).map do |lookup_target, artifact_version, row_invalidation_key, payload|
          parsed_payload = JSON.parse(payload)
          {
            lookup_target: lookup_target,
            artifact_version: artifact_version,
            invalidation_key: row_invalidation_key,
            payload: parsed_payload,
            payload_digest: artifact_payload_digest(parsed_payload)
          }
        end
      end
    end

    def write_artifact(gem_name:, gem_version:, lookup_target:, artifact_kind:, payload:, invalidation_key:, artifact_version: nil)
      write_artifacts(
        [
          {
            gem_name: gem_name,
            gem_version: gem_version,
            lookup_target: lookup_target,
            artifact_kind: artifact_kind,
            payload: payload,
            invalidation_key: invalidation_key,
            artifact_version: artifact_version
          }
        ]
      )
    end

    def write_artifacts(artifacts)
      return true if artifacts.empty?

      with_database do |database|
        transaction_open = false

        begin
          database.execute("BEGIN IMMEDIATE TRANSACTION")
          transaction_open = true
          artifacts.each do |artifact|
            write_artifact_row(
              database,
              gem_name: artifact.fetch(:gem_name),
              gem_version: artifact.fetch(:gem_version),
              lookup_target: artifact.fetch(:lookup_target),
              artifact_kind: artifact.fetch(:artifact_kind),
              payload: artifact.fetch(:payload),
              invalidation_key: artifact.fetch(:invalidation_key),
              artifact_version: artifact[:artifact_version]
            )
          end
          database.execute("COMMIT")
          transaction_open = false
        ensure
          database.execute("ROLLBACK") if transaction_open
        end
      end

      true
    end

    private

    attr_reader :path

    def with_database(attempt = 0)
      FileUtils.mkdir_p(File.dirname(path))
      database = nil
      database = SQLite3::Database.new(path)
      database.busy_timeout = BUSY_TIMEOUT_MS
      ensure_schema!(database)
      yield database
    rescue SQLite3::BusyException, SQLite3::LockedException
      raise if attempt >= MAX_BUSY_RETRIES

      sleep(BUSY_RETRY_DELAY * (attempt + 1))
      with_database(attempt + 1) { |retry_database| yield retry_database }
    ensure
      database&.close
    end

    def ensure_schema!(database)
      database.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS cache_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      SQL

      schema_version = database.get_first_row(
        "SELECT value FROM cache_metadata WHERE key = ?",
        "schema_version"
      )&.first

      if schema_version.to_i != SCHEMA_VERSION
        database.execute_batch(<<~SQL)
          DROP TABLE IF EXISTS documentation_artifacts;
          DELETE FROM cache_metadata;
        SQL

        database.execute(
          "INSERT INTO cache_metadata (key, value) VALUES (?, ?)",
          "schema_version",
          SCHEMA_VERSION.to_s
        )
      end

      database.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS documentation_artifacts (
          gem_name TEXT NOT NULL,
          gem_version TEXT NOT NULL,
          lookup_target TEXT NOT NULL,
          artifact_kind TEXT NOT NULL,
          invalidation_key TEXT NOT NULL,
          artifact_version INTEGER NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (gem_name, gem_version, lookup_target, artifact_kind)
        );
      SQL
    end

    def serialize_loaded_gem(loaded_gem)
      {
        "name" => loaded_gem.name,
        "version" => loaded_gem.version,
        "summary" => loaded_gem.summary,
        "description" => loaded_gem.description,
        "homepage" => loaded_gem.homepage,
        "license" => loaded_gem.license,
        "path" => loaded_gem.path,
        "doc_source" => loaded_gem.doc_source.to_s,
        "entry_points" => loaded_gem.entry_points,
        "objects" => loaded_gem.objects.map { |object| serialize_entry(object) }
      }
    end

    def serialize_entry(entry)
      {
        "path" => entry.path,
        "name" => entry.name,
        "kind" => entry.kind.to_s,
        "visibility" => entry.visibility.to_s,
        "docstring" => entry.docstring,
        "signature" => entry.signature,
        "source_location" => entry.source_location,
        "superclass" => entry.superclass,
        "doc_source" => entry.doc_source.to_s,
        "tags" => entry.tags,
        "aliases" => entry.aliases
      }
    end

    def build_loaded_gem(payload)
      GemDocs::DocRegistry::LoadedGem.new(
        name: payload.fetch("name"),
        version: payload.fetch("version"),
        summary: payload["summary"],
        description: payload["description"],
        homepage: payload["homepage"],
        license: payload["license"],
        path: payload.fetch("path"),
        doc_source: payload.fetch("doc_source").to_sym,
        objects: Array(payload["objects"]).map { |entry| build_entry(entry) },
        entry_points: Array(payload["entry_points"])
      )
    end

    def build_entry(payload)
      GemDocs::DocRegistry::Entry.new(
        path: payload.fetch("path"),
        name: payload.fetch("name"),
        kind: payload.fetch("kind").to_sym,
        visibility: payload.fetch("visibility").to_sym,
        docstring: payload.fetch("docstring"),
        signature: payload.fetch("signature"),
        source_location: payload["source_location"],
        superclass: payload["superclass"],
        doc_source: payload.fetch("doc_source").to_sym,
        tags: symbolize_hash(payload["tags"] || {}),
        aliases: Array(payload["aliases"])
      )
    end

    def symbolize_hash(value)
      case value
      when Hash
        value.each_with_object(Hash.new) do |(key, nested_value), hash|
          hash[key.to_sym] = symbolize_hash(nested_value)
        end
      when Array
        value.map { |item| symbolize_hash(item) }
      else
        value
      end
    end

    def default_artifact_version(artifact_kind)
      ARTIFACT_VERSIONS.fetch(artifact_kind.to_sym)
    end

    def write_artifact_row(database, gem_name:, gem_version:, lookup_target:, artifact_kind:, payload:, invalidation_key:, artifact_version: nil)
      database.execute(
        <<~SQL,
          INSERT INTO documentation_artifacts (
            gem_name,
            gem_version,
            lookup_target,
            artifact_kind,
            invalidation_key,
            artifact_version,
            payload,
            updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
          ON CONFLICT(gem_name, gem_version, lookup_target, artifact_kind)
          DO UPDATE SET
            invalidation_key = excluded.invalidation_key,
            artifact_version = excluded.artifact_version,
            payload = excluded.payload,
            updated_at = CURRENT_TIMESTAMP
        SQL
        gem_name,
        gem_version,
        lookup_target,
        artifact_kind.to_s,
        invalidation_key,
        artifact_version || default_artifact_version(artifact_kind),
        JSON.generate(payload)
      )
    end

    def compressed_usable?(payload)
      return false unless payload
      return false if payload.is_a?(Hash) && payload["status"] == "insufficient"

      true
    end

    def artifact_payload_digest(payload)
      Digest::SHA256.hexdigest(JSON.generate(payload))
    end
  end
end
