# frozen_string_literal: true

require "bundler"

module GemDocs
  module Commands
    class Context < Base
      OUTPUT_FILES = {
        "claude" => "CLAUDE.md",
        "cursor" => ".cursorrules",
        "windsurf" => ".windsurfrules",
        "copilot" => File.join(".github", "copilot-instructions.md"),
        "json" => ".gem-docs-context.json"
      }.freeze
      FORMATS = [ *OUTPUT_FILES.keys, "all" ].freeze

      desc "Generate project gem context files"
      option :format,
             values: FORMATS,
             default: "all",
             desc: "Context output format"
      option :gems, desc: "Comma-separated gem names"
      option :output_dir, default: ".", desc: "Directory for generated context files"

      def call(format: "all", gems: nil, output_dir: ".", **_kwargs)
        loaded_gems = resolve_gem_names(gems).map { |gem_name| doc_registry.load_gem(gem_name, version: nil) }
        output_root = File.expand_path(output_dir, project_root)

        resolve_formats(format).each do |resolved_format|
          destination = File.join(output_root, OUTPUT_FILES.fetch(resolved_format))
          ensure_directory(File.dirname(destination))
          File.write(destination, GemDocs::Formatters::Context.for(resolved_format).call(gems: loaded_gems))
          out.puts(display_path_for(destination))
        end

        0
      end

      private

      def doc_registry
        @doc_registry ||= GemDocs::DocRegistry.new
      end

      def project_root
        Dir.pwd
      end

      def resolve_formats(format)
        format == "all" ? OUTPUT_FILES.keys : [ format ]
      end

      def resolve_gem_names(gems)
        return lockfile_gem_names if gems.nil? || gems.strip.empty?

        gems.split(",").map(&:strip).reject(&:empty?).uniq
      end

      def lockfile_gem_names
        Bundler::LockfileParser
          .new(Bundler.read_file(File.join(project_root, "Gemfile.lock")))
          .dependencies
          .keys
          .reject { |name| config.exclude_gems.include?(name) }
          .uniq
      rescue Errno::ENOENT
        raise GemDocs::ConfigurationError.new("Gemfile.lock not found in #{project_root}")
      end

      def display_path_for(destination)
        prefix = "#{project_root}/"
        destination.start_with?(prefix) ? destination.delete_prefix(prefix) : destination
      end

      def ensure_directory(path)
        parent = File.dirname(path)
        ensure_directory(parent) unless Dir.exist?(parent)
        Dir.mkdir(path) unless Dir.exist?(path)
      end
    end
  end
end
