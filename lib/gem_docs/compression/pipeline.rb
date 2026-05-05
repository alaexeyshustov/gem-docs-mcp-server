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
        normalized = normalize_compressor_payload(payload)
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

      def normalize_compressor_payload(payload)
        raise ArgumentError, "Compressor output must be a Hash or nil" unless payload.nil? || payload.is_a?(Hash)

        normalized = payload&.transform_keys(&:to_s) || {}
        return insufficient_payload("Compressor returned no structured payload") if normalized.empty?

        normalized["status"] = normalized.fetch("status").to_s
        normalized["reason"] = normalized["reason"].to_s if normalized.key?("reason") && !normalized["reason"].nil?
        normalized["insights"] = Array(normalized.fetch("insights")).map { |insight| stringify_insight(insight) }
        validate_payload!(normalized)
        normalized
      end

      def insufficient_payload(reason)
        {
          "status" => "insufficient",
          "reason" => reason,
          "insights" => []
        }
      end

      def validate_payload!(payload)
        unless OUTPUT_SCHEMA.fetch("properties").fetch("status").fetch("enum").include?(payload["status"])
          raise ArgumentError, "Compressor output has invalid status: #{payload['status'].inspect}"
        end

        raise ArgumentError, "Compressor output must include an insights array" unless payload["insights"].is_a?(Array)

        if payload.key?("reason") && !payload["reason"].is_a?(String)
          raise ArgumentError, "Compressor output reason must be a string"
        end

        payload["insights"].each do |insight|
          validate_insight!(insight)
        end
      end

      def validate_insight!(insight)
        raise ArgumentError, "Each insight must be an object" unless insight.is_a?(Hash)

        title = insight["title"]
        detail = insight["detail"]
        raise ArgumentError, "Each insight must include a string title" unless title.is_a?(String)
        raise ArgumentError, "Each insight must include a string detail" unless detail.is_a?(String)

        categories = insight["categories"]
        if !categories.nil? && (!categories.is_a?(Array) || categories.any? { |value| !value.is_a?(String) })
          raise ArgumentError, "Insight categories must be an array of strings"
        end

        version_scope = insight["version_scope"]
        return if version_scope.nil? || version_scope.is_a?(String)

        raise ArgumentError, "Insight version_scope must be a string"
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
