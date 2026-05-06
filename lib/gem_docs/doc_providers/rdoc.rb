# frozen_string_literal: true

module GemDocs
  module DocProviders
    class Rdoc
      def initialize(shell_runner:, loaded_gem_builder:)
        @shell_runner = shell_runner
        @loaded_gem_builder = loaded_gem_builder
        # @type var index_names: Hash[String, Array[String]?]
        index_names = {}
        @index_names = index_names
      end

      def available?(spec)
        !index_names_for(spec).nil?
      end

      def load(spec)
        names = index_names_for(spec)
        return if names.nil? || names.empty?

        @loaded_gem_builder.call(
          spec,
          names.map { |name| build_index_entry(name) },
          :rdoc,
          dynamic_lookup: ->(path) { lookup(spec, path) },
          lazy_paths: names
        )
      end

      def lookup(spec, path)
        response = run_shell(ri_command(spec, path))
        return unless response[:success]

        signature, docstring = parse_output(response[:stdout])
        build_entry(path, signature, docstring)
      end

      def hydrate_loaded_gem(spec, loaded_gem)
        @loaded_gem_builder.call(
          spec,
          loaded_gem.objects,
          :rdoc,
          dynamic_lookup: ->(path) { lookup(spec, path) },
          lazy_paths: loaded_gem.objects.map(&:path)
        )
      end

      private

      def index_names_for(spec)
        cache_key = spec.full_gem_path
        return @index_names[cache_key] if @index_names.key?(cache_key)
        return @index_names[cache_key] = nil unless File.directory?(spec.doc_dir)

        response = run_shell(ri_list_command(spec))
        return @index_names[cache_key] = nil if command_execution_failed?(response)

        raise GemDocs::RegistryError.new("Failed to load ri registry: #{response[:stderr]}") unless response[:success]

        names = response[:stdout].lines.map(&:strip).reject(&:empty?)
        @index_names[cache_key] = names.empty? ? nil : names
      end

      def build_index_entry(name)
        GemDocs::DocRegistry::Entry.new(
          path: name,
          name: name.split("::").last,
          kind: :class,
          visibility: :public,
          docstring: "",
          signature: name,
          source_location: nil,
          superclass: nil,
          doc_source: :rdoc,
          tags: {},
          aliases: []
        )
      end

      def build_entry(path, signature, docstring)
        GemDocs::DocRegistry::Entry.new(
          path: path,
          name: path.split(/[#.]/).last,
          kind: kind_for(path, signature),
          visibility: :public,
          docstring: docstring,
          signature: signature.empty? ? path : signature,
          source_location: nil,
          superclass: nil,
          doc_source: :rdoc,
          tags: {},
          aliases: []
        )
      end

      def parse_output(output)
        lines = output.lines.map(&:rstrip)
        signature = lines.first.to_s.strip
        separator_index = lines.index("")
        doc_lines = if separator_index
          lines[(separator_index + 1)..]
        else
          lines[1..]
        end

        [ signature, Array(doc_lines).join("\n").strip ]
      end

      def kind_for(path, signature)
        return :instance_method if path.include?("#")
        return :class_method if path.match?(/\.[A-Za-z_]/)
        return :constant if path.split("::").last == path.split("::").last.upcase
        return :module if signature.start_with?("module ")

        :class
      end

      def ri_list_command(spec)
        [ "ri", "--no-pager", "--no-standard-docs", "-d", spec.doc_dir, "-l" ]
      end

      def ri_command(spec, *arguments)
        [ "ri", "--no-pager", "--no-standard-docs", "-d", spec.doc_dir, "--", *arguments ]
      end

      def run_shell(command)
        @shell_runner.call(command)
      rescue SystemCallError => e
        { stdout: "", stderr: e.message, success: false, error: e }
      end

      def command_execution_failed?(response)
        response[:error].is_a?(SystemCallError)
      end
    end
  end
end
