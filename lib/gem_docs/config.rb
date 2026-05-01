# frozen_string_literal: true

require "yaml"

module GemDocs
  class Config
    FILE_NAME = ".gem-docs.yml"
    DEFAULTS = {
      gems: {
        exclude: []
      },
      doc_fallback: {
        use_rdoc: true,
        use_source_prism: true
      },
      output: {
        color: "auto"
      }
    }.freeze

    def self.load(root: Dir.pwd)
      new(deep_merge(DEFAULTS, load_overrides(root)))
    end

    def initialize(values)
      @values = deep_freeze(values)
    end

    def to_h
      self.class.deep_dup(@values)
    end

    def exclude_gems
      @values.dig(:gems, :exclude)
    end

    def use_rdoc?
      @values.dig(:doc_fallback, :use_rdoc)
    end

    def use_source_prism?
      @values.dig(:doc_fallback, :use_source_prism)
    end

    def output_color
      @values.dig(:output, :color)
    end

    class << self
      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), duplicate|
            duplicate[key] = deep_dup(nested_value)
          end
        when Array
          value.map { |item| deep_dup(item) }
        else
          value
        end
      end

      private

      def load_overrides(root)
        path = File.join(root, FILE_NAME)
        return {} unless File.exist?(path)

        normalize_hash(YAML.safe_load(File.read(path), aliases: false) || {})
      end

      def normalize_hash(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), normalized|
            normalized[key.to_sym] = normalize_hash(nested_value)
          end
        when Array
          value.map { |item| normalize_hash(item) }
        else
          value
        end
      end

      def deep_merge(base, overrides)
        base.merge(overrides) do |_key, base_value, override_value|
          if base_value.is_a?(Hash) && override_value.is_a?(Hash)
            deep_merge(base_value, override_value)
          else
            override_value
          end
        end
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each_value { |nested_value| deep_freeze(nested_value) }
        when Array
          value.each { |item| deep_freeze(item) }
        end

        value.freeze
      end
    end

    private

    def deep_freeze(value)
      self.class.send(:deep_freeze, value)
    end
  end
end
