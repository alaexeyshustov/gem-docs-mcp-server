# frozen_string_literal: true

require "open3"
require "prism"
require "yard"
require "digest"

module GemDocs
  class DocRegistry
    YARD_MUTEX = Mutex.new
    private_constant :YARD_MUTEX

    class Entry < Data.define(
      :path,
      :name,
      :kind,
      :visibility,
      :docstring,
      :signature,
      :source_location,
      :superclass,
      :doc_source,
      :tags,
      :aliases
    )
      def class_or_module?
        kind == :class || kind == :module
      end
    end

    class LoadedGem
      MISSING = Object.new
      private_constant :MISSING

      attr_reader :name, :version, :summary, :description, :homepage, :license, :path, :doc_source, :objects,
                  :entry_points

      def initialize(
        name:,
        version:,
        summary:,
        path:,
        doc_source:,
        objects:,
        description: nil,
        homepage: nil,
        license: nil,
        entry_points: [],
        dynamic_lookup: nil,
        lazy_paths: []
      )
        @name = name
        @version = version
        @summary = summary
        @description = description
        @homepage = homepage
        @license = license
        @path = path
        @doc_source = doc_source
        @objects = objects.dup
        @entry_points = entry_points.dup
        @dynamic_lookup = dynamic_lookup
        @lazy_paths = lazy_paths.each_with_object({}) do |lazy_path, pending|
          pending[lazy_path] = true
        end
        @object_map = objects.each_with_object({}) do |object, map|
          map[object.path] = object
        end
      end

      def find(path)
        cached = @object_map[path]
        return nil if cached.equal?(MISSING)

        if @lazy_paths.delete(path)
          return cache_lookup(path, @dynamic_lookup&.call(path), fallback: cached)
        end

        return cached if cached

        cache_lookup(path, @dynamic_lookup&.call(path))
      end

      def classes
        @lazy_paths.keys.each { |path| find(path) }
        @objects.select(&:class_or_module?)
      end

      private

      def cache_lookup(path, result, fallback: nil)
        cached = result || fallback || MISSING
        @object_map[path] = cached

        if cached.equal?(MISSING)
          nil
        else
          replace_object(path, cached)
          cached
        end
      end

      def replace_object(path, object)
        index = @objects.index { |existing| existing.path == path }

        if index
          @objects[index] = object
        else
          @objects << object
        end
      end
    end

    class << self
      def gem_spec_for(name, version: nil)
        return Gem::Specification.find_by_name(name) if version.nil? || version.empty?

        Gem::Specification.find_by_name(name, version)
      rescue Gem::LoadError
        nil
      end
    end

    def initialize(shell_runner: nil, cache: nil, gem_loader: nil)
      @loaded_gems = {}
      @doc_sources = {}
      @shell_runner = shell_runner || method(:run_command)
      @cache = cache == false ? nil : (cache || GemDocs::ArtifactCache.default(root: Dir.pwd))
      @gem_loader = gem_loader || GemLoader.new(
        spec_resolver: self.class.method(:gem_spec_for),
        doc_source_detector: method(:detect_doc_source),
        source_loader: method(:load_source_objects),
        loaded_gem_builder: lambda do |spec, objects, doc_source|
          build_source_loaded_gem(spec, objects: objects, doc_source: doc_source)
        end
      )
    end

    def load_gem(name, version: nil)
      cache_key = cache_key_for(name, version)
      loaded_gem = @loaded_gems[cache_key]
      return loaded_gem if loaded_gem

      normalized_version = normalize_version(version)
      spec = @gem_loader.resolve_spec!(name, version: normalized_version)

      invalidation_key = safe_artifact_invalidation_key(spec)
      cached_gem = fetch_cached_loaded_gem(spec, invalidation_key: invalidation_key)
      if cached_gem
        @doc_sources[cache_key] = cached_gem.doc_source
        @loaded_gems[cache_key] = cached_gem
        ensure_source_artifacts_persisted(cached_gem, invalidation_key: invalidation_key)
        return cached_gem
      end

      loaded_gem = @gem_loader.load(name, version: normalized_version, spec: spec) || build_loaded_gem(spec)
      @doc_sources[cache_key] = loaded_gem.doc_source
      persist_loaded_gem(loaded_gem, invalidation_key: invalidation_key)
      @loaded_gems[cache_key] = loaded_gem
    end

    def doc_source_for(name, version: nil, spec: nil)
      cache_key = cache_key_for(name, version || spec&.version&.to_s)
      loaded_gem = @loaded_gems[cache_key]
      return loaded_gem.doc_source if loaded_gem

      normalized_version = normalize_version(version)
      spec ||= @gem_loader.resolve_spec!(name, version: normalized_version)

      @doc_sources.fetch(cache_key) do
        @doc_sources[cache_key] = @gem_loader.detect_source(spec)
      end
    end

    def artifact_invalidation_key_for(name, version: nil)
      spec = @gem_loader.resolve_spec!(name, version: version)
      safe_artifact_invalidation_key(spec)
    end

    def source_artifacts_for(name, version: nil)
      loaded_gem = load_gem(name, version: version)
      invalidation_key = artifact_invalidation_key_for(name, version: loaded_gem.version)
      return [] unless @cache && invalidation_key

      ensure_source_artifacts_persisted(loaded_gem, invalidation_key: invalidation_key)
    end

    def lookup_artifact_for(path, gem_name:, version: nil)
      loaded_gem = load_gem(gem_name, version: version)
      invalidation_key = artifact_invalidation_key_for(gem_name, version: loaded_gem.version)
      return unless @cache && invalidation_key

      @cache.fetch_with_fallback(
        gem_name: loaded_gem.name,
        gem_version: loaded_gem.version,
        lookup_target: path,
        invalidation_key: invalidation_key
      )
    rescue StandardError
      nil
    end

    def find_object(path, gem_name:)
      loaded_gem = load_gem(gem_name)
      loaded_gem.find(path) || find_in_ancestor_chain(loaded_gem, path)
    end

    def classes_for(gem_name)
      load_gem(gem_name).classes.sort_by(&:path)
    end

    def find_core_object(path)
      response = run_shell(*ri_core_command(path))
      return unless response[:success]

      signature, docstring = parse_rdoc_output(response[:stdout])
      Entry.new(
        path: path,
        name: path.split(/[#.]/).last,
        kind: rdoc_kind_for(path, signature),
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

    private

    def detect_doc_source(spec)
      return :yard if File.exist?(yardoc_path_for(spec))
      return :rdoc if rdoc_available?(spec)
      return :source_only if source_objects_available?(spec)

      :none
    end

    def artifact_invalidation_key(spec)
      digest = Digest::SHA256.new
      digest << "schema:#{GemDocs::ArtifactCache::SCHEMA_VERSION}\n"
      digest << "gem:#{spec.name}\n"
      digest << "version:#{spec.version}\n"
      digest << "path:#{spec.full_gem_path}\n"

      artifact_files_for(spec).sort.each do |file|
        stat = File.stat(file)
        digest << "file:#{file.delete_prefix("#{spec.full_gem_path}/")}\n"
        digest << "size:#{stat.size}\n"
        digest << "mtime:#{stat.mtime.to_r}\n"
      end

      digest.hexdigest
    end

    def artifact_files_for(spec)
      files = ruby_files_for(spec)
      yardoc = yardoc_path_for(spec)
      files << yardoc if File.file?(yardoc)
      files.uniq
    end

    def safe_artifact_invalidation_key(spec)
      artifact_invalidation_key(spec)
    rescue StandardError
      nil
    end

    def fetch_cached_loaded_gem(spec, invalidation_key:)
      return unless @cache && invalidation_key

      cached_gem = @cache.fetch_loaded_gem(
        gem_name: spec.name,
        gem_version: spec.version.to_s,
        invalidation_key: invalidation_key
      )
      return unless cached_gem

      hydrate_cached_loaded_gem(spec, cached_gem)
    rescue StandardError
      nil
    end

    def persist_loaded_gem(loaded_gem, invalidation_key:)
      return unless @cache && invalidation_key

      @cache.write_loaded_gem(loaded_gem, invalidation_key: invalidation_key)
      persist_source_artifacts(loaded_gem, invalidation_key: invalidation_key)
    rescue StandardError
      nil
    end

    def persist_source_artifacts(loaded_gem, invalidation_key:)
      loaded_gem.objects.dup.each do |entry|
        resolved_entry = loaded_gem.find(entry.path) || entry
        @cache.write_artifact(
          gem_name: loaded_gem.name,
          gem_version: loaded_gem.version,
          lookup_target: resolved_entry.path,
          artifact_kind: :source,
          payload: source_artifact_payload(loaded_gem, resolved_entry),
          invalidation_key: invalidation_key
        )
      end
    end

    def ensure_source_artifacts_persisted(loaded_gem, invalidation_key:)
      return [] unless @cache && invalidation_key

      artifacts = @cache.source_artifacts(
        gem_name: loaded_gem.name,
        gem_version: loaded_gem.version,
        invalidation_key: invalidation_key
      )
      return artifacts unless artifacts.empty? && !loaded_gem.objects.empty?

      persist_source_artifacts(loaded_gem, invalidation_key: invalidation_key)
      @cache.source_artifacts(
        gem_name: loaded_gem.name,
        gem_version: loaded_gem.version,
        invalidation_key: invalidation_key
      )
    rescue StandardError
      []
    end

    def source_artifact_payload(loaded_gem, entry)
      {
        "gem_name" => loaded_gem.name,
        "gem_version" => loaded_gem.version,
        "doc_source" => entry.doc_source.to_s,
        "path" => entry.path,
        "name" => entry.name,
        "kind" => entry.kind.to_s,
        "visibility" => entry.visibility.to_s,
        "docstring" => entry.docstring,
        "signature" => entry.signature,
        "source_location" => entry.source_location,
        "superclass" => entry.superclass,
        "tags" => stringify_hash(entry.tags),
        "aliases" => entry.aliases
      }
    end

    def hydrate_cached_loaded_gem(spec, loaded_gem)
      return loaded_gem unless loaded_gem.doc_source == :rdoc

      LoadedGem.new(
        name: loaded_gem.name,
        version: loaded_gem.version,
        summary: loaded_gem.summary,
        description: loaded_gem.description,
        homepage: loaded_gem.homepage,
        license: loaded_gem.license,
        path: loaded_gem.path,
        doc_source: loaded_gem.doc_source,
        objects: loaded_gem.objects,
        entry_points: loaded_gem.entry_points,
        dynamic_lookup: ->(path) { load_rdoc_object(spec, path) },
        lazy_paths: loaded_gem.objects.map(&:path)
      )
    end

    def cache_key_for(name, version)
      normalized_version = normalize_version(version)
      return name if normalized_version.nil?

      [ name, normalized_version ].freeze
    end

    def normalize_version(version)
      return nil if version.nil? || version.empty?

      version
    end

    def resolve_spec(name, version: nil)
      @gem_loader.resolve_spec!(name, version: version)
    rescue GemDocs::GemNotFound
      nil
    end

    def build_loaded_gem(spec)
      loaded_gem = if File.exist?(yardoc_path_for(spec))
        objects = load_yard_objects(yardoc_path_for(spec))
        LoadedGem.new(
          name: spec.name,
          version: spec.version.to_s,
          summary: spec.summary,
          description: gem_description(spec),
          homepage: spec.homepage,
          license: gem_license(spec),
          path: spec.full_gem_path,
          doc_source: :yard,
          objects: objects,
          entry_points: infer_entry_points(spec.name, objects, doc_source: :yard)
        )
      elsif (rdoc_objects = load_rdoc_objects(spec))
        LoadedGem.new(
          name: spec.name,
          version: spec.version.to_s,
          summary: spec.summary,
          description: gem_description(spec),
          homepage: spec.homepage,
          license: gem_license(spec),
          path: spec.full_gem_path,
          doc_source: :rdoc,
          objects: rdoc_objects,
          entry_points: infer_entry_points(spec.name, rdoc_objects, doc_source: :rdoc),
          dynamic_lookup: ->(path) { load_rdoc_object(spec, path) },
          lazy_paths: rdoc_objects.map(&:path)
        )
      else
        objects = load_source_objects(spec)
        build_source_loaded_gem(spec, objects: objects, doc_source: objects.empty? ? :none : :source_only)
      end

      loaded_gem
    end

    def build_source_loaded_gem(spec, objects:, doc_source:)
      LoadedGem.new(
        name: spec.name,
        version: spec.version.to_s,
        summary: spec.summary,
        description: gem_description(spec),
        homepage: spec.homepage,
        license: gem_license(spec),
        path: spec.full_gem_path,
        doc_source: doc_source,
        objects: objects,
        entry_points: infer_entry_points(spec.name, objects, doc_source: doc_source)
      )
    end

    def load_yard_objects(yardoc)
      YARD_MUTEX.synchronize do
        previous_yardoc = YARD::Registry.yardoc_file
        YARD::Registry.clear
        YARD::Registry.load!(yardoc)

        objects = []
        queue = YARD::Registry.root.children.reverse

        until queue.empty?
          object = queue.pop

          case object
          when YARD::CodeObjects::ClassObject, YARD::CodeObjects::ModuleObject
            objects << build_yard_namespace_entry(object)
            queue.concat(object.constants(inherited: false).reverse)
            queue.concat(object.meths(inherited: false).reverse)
            queue.concat(object.children.grep(YARD::CodeObjects::NamespaceObject).reverse)
          when YARD::CodeObjects::MethodObject
            objects << build_yard_method_entry(object)
          when YARD::CodeObjects::ConstantObject
            objects << build_yard_constant_entry(object)
          end
        end

        objects
      ensure
        YARD::Registry.clear
        YARD::Registry.yardoc_file = previous_yardoc
      end
    rescue StandardError => e
      raise GemDocs::RegistryError.new("Failed to load YARD registry: #{e.message}")
    end

    def gem_description(spec)
      description = spec.description.to_s.strip
      return description unless description.empty?

      spec.summary
    end

    def gem_license(spec)
      licenses = Array(spec.licenses).filter_map do |value|
        normalized = value.to_s.strip
        normalized unless normalized.empty?
      end
      return licenses.first unless licenses.empty?

      license = spec.respond_to?(:license) ? spec.license.to_s.strip : ""
      license.empty? ? nil : license
    end

    def infer_entry_points(gem_name, objects, doc_source:)
      return [] if doc_source == :source_only || doc_source == :none

      classes = objects.select(&:class_or_module?).sort_by(&:path)
      methods = objects.select do |object|
        [ :class_method, :instance_method ].include?(object.kind) && object.visibility == :public
      end.sort_by(&:path)

      entry_points = []
      primary_class = select_primary_class(classes, gem_name)
      entry_points << "#{primary_class.path}.new" if primary_class&.kind == :class
      entry_points.concat(methods.reject { |object| object.name == "initialize" }.map(&:path))
      entry_points.uniq.first(3)
    end

    def select_primary_class(classes, gem_name)
      namespace = gem_name.split(/[^a-zA-Z0-9]+/).reject(&:empty?).map(&:capitalize).join

      classes.find { |entry| entry.kind == :class && entry.path == namespace } ||
        classes.find { |entry| entry.kind == :class && !entry.path.include?("::") } ||
        classes.find { |entry| entry.kind == :module && entry.path == namespace } ||
        classes.find { |entry| !entry.path.include?("::") } ||
        classes.first
    end

    def load_rdoc_objects(spec)
      return unless File.directory?(spec.doc_dir)

      response = run_shell(*ri_list_command(spec))
      return if command_execution_failed?(response)

      raise GemDocs::RegistryError.new("Failed to load ri registry: #{response[:stderr]}") unless response[:success]

      names = response[:stdout].lines.map(&:strip).reject(&:empty?)
      return if names.empty?

      names.map do |name|
        build_rdoc_index_entry(name)
      end
    end

    def yardoc_path_for(spec)
      File.join(spec.full_gem_path, ".yardoc")
    end

    def rdoc_available?(spec)
      return false unless File.directory?(spec.doc_dir)

      response = run_shell(*ri_list_command(spec))
      return false if command_execution_failed?(response)

      raise GemDocs::RegistryError.new("Failed to load ri registry: #{response[:stderr]}") unless response[:success]

      response[:stdout].each_line.any? { |line| !line.strip.empty? }
    end

    def build_rdoc_index_entry(name)
      Entry.new(
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

    def load_rdoc_object(spec, path)
      response = run_shell(*ri_command(spec, path))
      return unless response[:success]

      signature, docstring = parse_rdoc_output(response[:stdout])
      Entry.new(
        path: path,
        name: path.split(/[#.]/).last,
        kind: rdoc_kind_for(path, signature),
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

    def build_yard_namespace_entry(object)
      Entry.new(
        path: object.path,
        name: object.name.to_s,
        kind: object.is_a?(YARD::CodeObjects::ClassObject) ? :class : :module,
        visibility: object.visibility || :public,
        docstring: object.docstring.to_s,
        signature: object.path,
        source_location: yard_source_location(object),
        superclass: yard_superclass(object),
        doc_source: :yard,
        tags: yard_tags(object),
        aliases: yard_aliases(object)
      )
    end

    def build_yard_method_entry(object)
      Entry.new(
        path: object.path,
        name: object.name.to_s,
        kind: object.scope == :class ? :class_method : :instance_method,
        visibility: object.visibility || :public,
        docstring: object.docstring.to_s,
        signature: object.signature || object.path,
        source_location: yard_source_location(object),
        superclass: nil,
        doc_source: :yard,
        tags: yard_tags(object),
        aliases: yard_aliases(object)
      )
    end

    def build_yard_constant_entry(object)
      Entry.new(
        path: object.path,
        name: object.name.to_s,
        kind: :constant,
        visibility: object.visibility || :public,
        docstring: object.docstring.to_s,
        signature: object.path,
        source_location: yard_source_location(object),
        superclass: nil,
        doc_source: :yard,
        tags: yard_tags(object),
        aliases: yard_aliases(object)
      )
    end

    def load_source_objects(spec)
      ruby_files_for(spec).flat_map do |file|
        parse_source_file(file)
      end
    end

    def source_objects_available?(spec)
      ruby_files_for(spec).any? do |file|
        source_file_has_documentable_objects?(file)
      end
    end

    def ruby_files_for(spec)
      Array(spec.require_paths).flat_map do |require_path|
        Dir.glob(File.join(spec.full_gem_path, require_path, "**", "*.rb"))
      end.sort
    end

    def source_file_has_documentable_objects?(file)
      stack = [ Prism.parse_file(file).value ]

      until stack.empty?
        node = stack.pop
        return true if documentable_source_node?(node)
        next unless node.respond_to?(:compact_child_nodes)

        node.compact_child_nodes.each do |child|
          stack << child
        end
      end

      false
    end

    def documentable_source_node?(node)
      case node
      when Prism::ClassNode, Prism::ModuleNode, Prism::DefNode, Prism::ConstantWriteNode
        true
      else
        false
      end
    end

    def parse_source_file(file)
      result = Prism.parse_file(file)
      stack = [ [ result.value, nil, false ] ]
      objects = []

      until stack.empty?
        node, namespace_path, class_method_context = stack.pop

        case node
        when Prism::ClassNode
          class_path = join_constant_path(namespace_path, node.constant_path.slice)
          objects << build_namespace_entry(
            path: class_path,
            kind: :class,
            file: file,
            line: node.location.start_line,
            superclass: resolve_constant_reference(namespace_path, node.superclass&.slice)
          )
          push_children(stack, node, class_path)
        when Prism::ModuleNode
          module_path = join_constant_path(namespace_path, node.constant_path.slice)
          objects << build_namespace_entry(
            path: module_path,
            kind: :module,
            file: file,
            line: node.location.start_line
          )
          push_children(stack, node, module_path)
        when Prism::SingletonClassNode
          next unless node.expression.is_a?(Prism::SelfNode)

          push_children(stack, node, namespace_path, true)
        when Prism::DefNode
          next unless namespace_path

          class_method = class_method_context || node.receiver.is_a?(Prism::SelfNode)
          method_path = if class_method
            "#{namespace_path}.#{node.name}"
          else
            "#{namespace_path}##{node.name}"
          end
          objects << Entry.new(
            path: method_path,
            name: node.name.to_s,
            kind: class_method ? :class_method : :instance_method,
            visibility: :public,
            docstring: "",
            signature: build_method_signature(namespace_path, node, class_method: class_method),
            source_location: format_source_location(file, node.location.start_line),
            superclass: nil,
            doc_source: :source_only,
            tags: {},
            aliases: []
          )
        when Prism::ConstantWriteNode
          constant_path = join_constant_path(namespace_path, node.name.to_s)
          objects << Entry.new(
            path: constant_path,
            name: node.name.to_s,
            kind: :constant,
            visibility: :public,
            docstring: "",
            signature: constant_path,
            source_location: format_source_location(file, node.location.start_line),
            superclass: nil,
            doc_source: :source_only,
            tags: {},
            aliases: []
          )
        else
          push_children(stack, node, namespace_path, class_method_context)
        end
      end

      objects
    end

    def build_namespace_entry(path:, kind:, file:, line:, superclass: nil)
      Entry.new(
        path: path,
        name: path.split("::").last,
        kind: kind,
        visibility: :public,
        docstring: "",
        signature: path,
        source_location: format_source_location(file, line),
        superclass: superclass,
        doc_source: :source_only,
        tags: {},
        aliases: []
      )
    end

    def build_method_signature(namespace_path, node, class_method:)
      receiver_separator = class_method ? "." : "#"
      parameter_list = format_parameter_list(node.parameters&.signature || [])
      "#{namespace_path}#{receiver_separator}#{node.name}(#{parameter_list.join(', ')})"
    end

    def format_parameter_list(parameters)
      parameters.map do |type, name|
        case type
        when :req
          name.to_s
        when :opt
          "#{name} = ?"
        when :rest
          "*#{name}"
        when :post
          name.to_s
        when :keyreq
          "#{name}:"
        when :key
          "#{name}: ?"
        when :keyrest
          "**#{name}"
        when :block
          "&#{name}"
        else
          name.to_s
        end
      end
    end

    def join_constant_path(namespace_path, constant_path)
      return constant_path unless namespace_path

      "#{namespace_path}::#{constant_path}"
    end

    def resolve_constant_reference(namespace_path, constant_path)
      return if constant_path.nil?
      return constant_path if constant_path.include?("::") || namespace_path.nil?

      "#{namespace_path}::#{constant_path}"
    end

    def format_source_location(file, line)
      "#{file}:#{line}"
    end

    def yard_source_location(object)
      return unless object.file && object.line

      format_source_location(object.file, object.line)
    end

    def yard_superclass(object)
      return unless object.is_a?(YARD::CodeObjects::ClassObject)

      superclass = object.superclass
      return unless superclass

      superclass.respond_to?(:path) ? superclass.path : superclass.to_s
    end

    def yard_tags(object)
      return {} unless object.respond_to?(:tags)

      object.tags.each_with_object({}) do |tag, grouped_tags|
        normalized = normalize_yard_tag(tag)
        next if normalized.nil?

        grouped_tags[tag.tag_name.to_sym] ||= []
        grouped_tags[tag.tag_name.to_sym] << normalized
      end
    end

    def normalize_yard_tag(tag)
      return tag.text.to_s.strip if tag.tag_name == "example"

      payload = {}
      payload[:name] = tag.name if tag.respond_to?(:name) && tag.name
      payload[:types] = Array(tag.types).map(&:to_s) if tag.respond_to?(:types)
      payload[:text] = tag.text.to_s.strip
      payload
    end

    def yard_aliases(object)
      return [] unless object.respond_to?(:aliases)

      Array(object.aliases).filter_map do |alias_object|
        alias_object.respond_to?(:path) ? alias_object.path : alias_object.to_s
      end
    end

    def stringify_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), hash|
          hash[key.to_s] = stringify_hash(nested_value)
        end
      when Array
        value.map { |item| stringify_hash(item) }
      else
        value
      end
    end

    def parse_rdoc_output(output)
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

    def rdoc_kind_for(path, signature)
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

    def ri_core_command(*arguments)
      [ "ri", "--no-pager", "--", *arguments ]
    end

    def run_shell(*command)
      @shell_runner.call(command)
    rescue SystemCallError => e
      { stdout: "", stderr: e.message, success: false, error: e }
    end

    def run_command(command)
      stdout, stderr, status = Open3.capture3(*command)
      { stdout: stdout, stderr: stderr, success: status.success? }
    rescue SystemCallError => e
      { stdout: "", stderr: e.message, success: false, error: e }
    end

    def command_execution_failed?(response)
      response[:error].is_a?(SystemCallError)
    end

    def push_children(stack, node, namespace_path, class_method_context = false)
      return unless node.respond_to?(:compact_child_nodes)

      node.compact_child_nodes.reverse_each do |child|
        stack << [ child, namespace_path, class_method_context ]
      end
    end

    def find_in_ancestor_chain(loaded_gem, path)
      namespace_path, separator, method_name = path.match(/\A(.+)([#.])([^#.]+)\z/)&.captures
      return unless namespace_path

      visited = {}
      current_namespace = namespace_path

      until current_namespace.nil? || visited[current_namespace]
        visited[current_namespace] = true

        namespace_object = loaded_gem.find(current_namespace)
        current_namespace = namespace_object&.superclass
        next unless current_namespace

        match = loaded_gem.find("#{current_namespace}#{separator}#{method_name}")
        return match if match
      end
    end
  end
end
