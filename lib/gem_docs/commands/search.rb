# frozen_string_literal: true

module GemDocs
  module Commands
    class Search < Base
      PER_GEM_LIMIT = 5

      desc "Search gem documentation"
      argument :query, type: :string
      option :gem, desc: "Gem name"
      option :scope, values: %w[methods classes all], default: "all", desc: "Search scope"
      option :limit, default: "10", desc: "Maximum results"

      def call(query:, gem: nil, scope: "all", limit: "10", format: "text", **_kwargs)
        results = if gem
          search_gem(query, gem, scope: scope, limit: normalize_limit(limit))
        else
          search_all_gems(query, scope: scope, limit: normalize_limit(limit))
        end

        out.puts GemDocs::Formatters.for(format).search(results: results)
        0
      end

      private

      def doc_registry
        @doc_registry ||= GemDocs::DocRegistry.new
      end

      def installed_specs
        Gem::Specification.to_a.sort_by(&:name)
      end

      def search_gem(query, gem_name, scope:, limit:)
        loaded_gem = doc_registry.load_gem(gem_name)
        return [] if loaded_gem.doc_source == :none

        ranked_results_for(loaded_gem, query, scope: scope).first(limit)
      end

      def search_all_gems(query, scope:, limit:)
        installed_specs
          .reject { |spec| config.exclude_gems.include?(spec.name) }
          .flat_map do |spec|
            safe_ranked_results_for(spec.name, query, scope: scope)
          end
          .sort_by { |result| [ -result.fetch(:score), result.fetch(:path), result.fetch(:gem) ] }
          .first(limit)
      end

      def safe_ranked_results_for(gem_name, query, scope:)
        loaded_gem = doc_registry.load_gem(gem_name)
        return [] if loaded_gem.doc_source == :none

        ranked_results_for(loaded_gem, query, scope: scope).first(PER_GEM_LIMIT)
      rescue GemDocs::RegistryError, GemDocs::DocUnavailable
        []
      end

      def ranked_results_for(loaded_gem, query, scope:)
        loaded_gem.objects
          .filter_map do |entry|
            next unless searchable_entry?(entry, scope)

            resolved_entry = loaded_gem.find(entry.path) || entry
            score = score_for(resolved_entry, query)
            next unless score

            search_payload(resolved_entry, gem_name: loaded_gem.name, score: score)
          end
          .uniq { |result| [ result.fetch(:gem), result.fetch(:path) ] }
          .sort_by { |result| [ -result.fetch(:score), result.fetch(:path), result.fetch(:gem) ] }
      end

      def searchable_entry?(entry, scope)
        return false unless entry.visibility == :public
        return false if anonymous_entry?(entry)

        case scope
        when "methods"
          method_entry?(entry)
        when "classes"
          class_entry?(entry)
        else
          method_entry?(entry) || class_entry?(entry)
        end
      end

      def anonymous_entry?(entry)
        path = entry.path.to_s.strip
        path.empty? || path.include?("#<")
      end

      def method_entry?(entry)
        [ :instance_method, :class_method ].include?(entry.kind)
      end

      def class_entry?(entry)
        [ :class, :module ].include?(entry.kind)
      end

      def score_for(entry, query)
        normalized_query = query.to_s.downcase.strip
        return if normalized_query.empty?

        normalized_path = entry.path.downcase
        normalized_name = entry.name.downcase
        normalized_summary = summary_for(entry).downcase
        segments = normalized_path.split(/::|#|\./)

        score = [
          (1.0 if normalized_path == normalized_query),
          (0.99 if normalized_name == normalized_query),
          (0.95 if segments.include?(normalized_query)),
          (0.85 if segments.any? { |segment| segment.include?(normalized_query) }),
          (0.75 if normalized_path.include?(normalized_query)),
          (0.65 if normalized_summary.split(/[^a-z0-9]+/).include?(normalized_query)),
          (0.55 if normalized_summary.include?(normalized_query))
        ].compact.max

        return unless score

        (Float(score) * 100).round / 100.0
      end

      def summary_for(entry)
        entry.docstring.to_s.lines.map(&:strip).reject(&:empty?).first.to_s
      end

      def search_payload(entry, gem_name:, score:)
        {
          path: entry.path,
          gem: gem_name,
          type: method_entry?(entry) ? "method" : entry.kind.to_s,
          summary: summary_for(entry),
          score: score
        }
      end

      def normalize_limit(limit)
        normalized_limit = limit.to_i
        normalized_limit.positive? ? normalized_limit : 10
      end
    end
  end
end
