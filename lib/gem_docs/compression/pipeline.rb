# frozen_string_literal: true

require "json"

module GemDocs
  module Compression
    class Pipeline
      PROMPT_VERSION = 1
      NON_OBVIOUS_KNOWLEDGE_DEFINITION = <<~TEXT.freeze
        Extract only gem-specific knowledge that is unlikely to be obvious from a strong model's prior knowledge:
        surprising behavior, caveats, conventions, edge cases, and version-specific details.
        If the source artifact contains only obvious API surface information, return status="insufficient".
      TEXT
      OUTPUT_SCHEMA = {
        "type" => "object",
        "required" => [ "status", "insights" ],
        "properties" => {
          "status" => {
            "type" => "string",
            "enum" => [ "ready", "insufficient" ]
          },
          "reason" => {
            "type" => "string"
          },
          "insights" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "required" => [ "title", "detail" ],
              "properties" => {
                "title" => { "type" => "string" },
                "detail" => { "type" => "string" },
                "categories" => {
                  "type" => "array",
                  "items" => { "type" => "string" }
                },
                "version_scope" => { "type" => "string" }
              }
            }
          }
        }
      }.freeze

      def initialize(cache:, compressor:, doc_registry: GemDocs::DocRegistry.new(cache: cache))
        @cache = cache
        @compressor = compressor
        @doc_registry = doc_registry
      end

      def compress_gem(gem_name, version: nil)
        loaded_gem = @doc_registry.load_gem(gem_name, version: version)
        invalidation_key = @doc_registry.artifact_invalidation_key_for(gem_name, version: loaded_gem.version)
        source_artifacts = @doc_registry.source_artifacts_for(gem_name, version: loaded_gem.version)

        source_artifacts.each do |source_artifact|
          compressed_payload = normalize_payload(
            @compressor.call(
              gem: {
                name: loaded_gem.name,
                version: loaded_gem.version,
                doc_source: loaded_gem.doc_source.to_s
              },
              source_artifact: source_artifact,
              prompt: prompt_for(loaded_gem, source_artifact),
              schema: OUTPUT_SCHEMA
            ),
            source_artifact: source_artifact
          )

          @cache.write_artifact(
            gem_name: loaded_gem.name,
            gem_version: loaded_gem.version,
            lookup_target: source_artifact.fetch(:lookup_target),
            artifact_kind: :compressed,
            payload: compressed_payload,
            invalidation_key: invalidation_key
          )
        end

        {
          gem_name: loaded_gem.name,
          gem_version: loaded_gem.version,
          compressed_count: source_artifacts.length
        }
      end

      private

      def prompt_for(loaded_gem, source_artifact)
        <<~TEXT
          Compress non-obvious knowledge for #{loaded_gem.name} #{loaded_gem.version}.

          #{NON_OBVIOUS_KNOWLEDGE_DEFINITION}

          Lookup target: #{source_artifact.fetch(:lookup_target)}
          Source payload:
          #{source_artifact.fetch(:payload).to_json}
        TEXT
      end

      def normalize_payload(payload, source_artifact:)
        normalized = (payload || {}).transform_keys(&:to_s)
        normalized["status"] ||= "ready"
        normalized["insights"] = Array(normalized["insights"]).map { |insight| stringify_insight(insight) }
        normalized["prompt_version"] = PROMPT_VERSION
        normalized["source_artifact"] = {
          "lookup_target" => source_artifact.fetch(:lookup_target),
          "artifact_kind" => "source",
          "artifact_version" => source_artifact.fetch(:artifact_version),
          "invalidation_key" => source_artifact.fetch(:invalidation_key),
          "payload_digest" => source_artifact.fetch(:payload_digest)
        }
        normalized
      end

      def stringify_insight(insight)
        case insight
        when Hash
          stringified = Hash.new
          insight.each do |key, value|
            stringified[key.to_s] = value
          end
          stringified
        else
          { "detail" => insight.to_s }
        end
      end
    end
  end
end
