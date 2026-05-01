# frozen_string_literal: true

require "yaml"

module GemDocs
  class Config
    FILE_NAME = ".gem-docs.yml"
    VALID_COLORS = %w[auto always never].freeze
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
        raw_config = YAML.safe_load(File.read(path), aliases: false) || {}
        unless raw_config.is_a?(Hash)
          raise GemDocs::ConfigurationError.new("#{path} must contain a YAML mapping")
        end

        normalized_config = normalize_hash(raw_config)
        validate_overrides!(normalized_config, path)
        normalized_config
      rescue Errno::ENOENT
        {}
      rescue Psych::SyntaxError => e
        raise GemDocs::ConfigurationError.new("Invalid configuration in #{path}: #{e.message}")
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
          if override_value.nil?
            base_value
          elsif base_value.is_a?(Hash) && override_value.is_a?(Hash)
            deep_merge(base_value, override_value)
          else
            override_value
          end
        end
      end

      def validate_overrides!(overrides, path)
        validate_section_hash!(overrides, :gems, path)
        validate_section_hash!(overrides, :doc_fallback, path)
        validate_section_hash!(overrides, :output, path)

        validate_array!(overrides.dig(:gems, :exclude), "#{path} gems.exclude") if overrides.dig(:gems, :exclude)
        validate_boolean!(overrides.dig(:doc_fallback, :use_rdoc), "#{path} doc_fallback.use_rdoc") if overrides.dig(:doc_fallback, :use_rdoc) != nil
        validate_boolean!(overrides.dig(:doc_fallback, :use_source_prism), "#{path} doc_fallback.use_source_prism") if overrides.dig(:doc_fallback, :use_source_prism) != nil

        return unless overrides.dig(:output, :color)

        validate_color!(overrides.dig(:output, :color), "#{path} output.color")
      end

      def validate_section_hash!(overrides, section, path)
        value = overrides[section]
        return if value.nil? || value.is_a?(Hash)

        raise GemDocs::ConfigurationError.new("#{path} #{section} must be a mapping")
      end

      def validate_array!(value, location)
        return if value.is_a?(Array)

        raise GemDocs::ConfigurationError.new("#{location} must be an array")
      end

      def validate_boolean!(value, location)
        return if value == true || value == false

        raise GemDocs::ConfigurationError.new("#{location} must be true or false")
      end

      def validate_color!(value, location)
        return if VALID_COLORS.include?(value)

        raise GemDocs::ConfigurationError.new("#{location} must be one of: #{VALID_COLORS.join(', ')}")
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
