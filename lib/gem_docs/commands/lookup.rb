# frozen_string_literal: true

module GemDocs
  module Commands
    class Lookup < Base
      desc "Look up a constant or method"
      argument :path, type: :string
      option :gem, desc: "Gem name"

      def call(path:, gem: nil, format: "text", **_kwargs)
        out.puts GemDocs::Formatters.for(format).lookup(result: lookup_payload(resolve(path, gem_name: gem)))
        0
      end

      private

      def doc_registry
        @doc_registry ||= GemDocs::DocRegistry.new
      end

      def installed_specs
        Gem::Specification.to_a.sort_by(&:name)
      end

      def resolve(path, gem_name:)
        return resolve_in_gem(path, gem_name) if gem_name

        matches = installed_specs.flat_map do |spec|
          lookup_matches(path, spec.name)
        end
        return matches.first if matches.one?
        raise GemDocs::AmbiguousLookup.new(path, candidates: candidate_labels(matches)) if matches.any?

        core_entry = doc_registry.find_core_object(path)
        return { gem_name: "ruby", version: RUBY_VERSION, entry: core_entry } if core_entry

        raise GemDocs::LookupNotFound.new(path)
      end

      def resolve_in_gem(path, gem_name)
        matches = lookup_matches(path, gem_name)
        return matches.first if matches.one?
        raise GemDocs::AmbiguousLookup.new(path, candidates: candidate_labels(matches)) if matches.any?

        raise GemDocs::LookupNotFound.new(path)
      end

      def lookup_matches(path, gem_name)
        loaded_gem = doc_registry.load_gem(gem_name)
        exact_match = doc_registry.find_object(path, gem_name: gem_name)
        return [ { gem_name: loaded_gem.name, version: loaded_gem.version, entry: exact_match } ] if exact_match

        fuzzy_matches = loaded_gem.objects.filter_map do |entry|
          next unless fuzzy_match?(entry.path, path)

          resolved_entry = loaded_gem.find(entry.path) || entry
          { gem_name: loaded_gem.name, version: loaded_gem.version, entry: resolved_entry }
        end

        fuzzy_matches.uniq do |match|
          entry = match.fetch(:entry)
          entry_path = entry.is_a?(GemDocs::DocRegistry::Entry) ? entry.path : entry.to_s
          [ match.fetch(:gem_name), entry_path ]
        end
      end

      def fuzzy_match?(candidate_path, query)
        normalized_candidate = candidate_path.downcase
        normalized_query = query.downcase
        return true if normalized_candidate == normalized_query

        suffix_index = normalized_candidate.rindex(normalized_query)
        prefix = suffix_index ? normalized_candidate[0...suffix_index].to_s : ""
        suffix = suffix_index ? normalized_candidate[(suffix_index + normalized_query.length)..].to_s : ""
        boundary_match = suffix.empty? || suffix.start_with?("::", "#", ".")
        return true if !prefix.empty? && prefix.end_with?("::", "#", ".") && boundary_match

        normalized_candidate.end_with?("::#{normalized_query}") ||
          normalized_candidate.end_with?("##{normalized_query}") ||
          normalized_candidate.end_with?(".#{normalized_query}") ||
          normalized_candidate.split(/::|#|\./).last == normalized_query
      end

      def candidate_labels(matches)
        duplicate_paths = matches.group_by { |match| match[:entry].path }.select { |_path, grouped| grouped.size > 1 }.keys

        matches.map do |match|
          label = match[:entry].path
          duplicate_paths.include?(label) ? "#{match[:gem_name]}:#{label}" : label
        end
      end

      def lookup_payload(result)
        entry = result.fetch(:entry)
        cached_artifact = doc_registry.lookup_artifact_for(
          entry.path,
          gem_name: result.fetch(:gem_name),
          version: result.fetch(:version)
        )

        payload = {
          path: entry.path,
          name: entry.name,
          kind: entry.kind,
          gem: result.fetch(:gem_name),
          version: result.fetch(:version),
          doc_source: entry.doc_source,
          visibility: entry.visibility,
          signature: entry.signature,
          docstring: entry.docstring,
          tags: entry.tags,
          source_location: entry.source_location,
          aliases: entry.aliases
        }

        return payload unless cached_artifact

        payload[:knowledge_source] = cached_artifact.fetch(:kind)
        if cached_artifact.fetch(:kind) == :compressed
          payload[:non_obvious_insights] = cached_artifact.fetch(:payload).fetch("insights", Array.new)
        end

        payload
      end
    end
  end
end
