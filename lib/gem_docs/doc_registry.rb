# frozen_string_literal: true

require "open3"
require "prism"
require "yard"

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
      :doc_source
    )
      def class_or_module?
        kind == :class || kind == :module
      end
    end

    class LoadedGem
      attr_reader :name, :version, :summary, :path, :doc_source, :objects

      def initialize(name:, version:, summary:, path:, doc_source:, objects:, dynamic_lookup: nil)
        @name = name
        @version = version
        @summary = summary
        @path = path
        @doc_source = doc_source
        @objects = objects.freeze
        @dynamic_lookup = dynamic_lookup
        @object_map = objects.each_with_object({}) do |object, map|
          map[object.path] = object
        end
      end

      def find(path)
        @object_map[path] ||= @dynamic_lookup&.call(path)
      end

      def classes
        objects.select(&:class_or_module?)
      end
    end

    class << self
      def gem_spec_for(name)
        Gem::Specification.find_by_name(name)
      rescue Gem::LoadError
        nil
      end
    end

    def initialize(shell_runner: nil)
      @loaded_gems = {}
      @shell_runner = shell_runner || method(:run_command)
    end

    def load_gem(name)
      @loaded_gems.fetch(name) do
        spec = self.class.gem_spec_for(name)
        raise GemDocs::GemNotFound.new(name) unless spec

        @loaded_gems[name] = build_loaded_gem(spec)
      end
    end

    def find_object(path, gem_name:)
      loaded_gem = load_gem(gem_name)
      loaded_gem.find(path) || find_in_ancestor_chain(loaded_gem, path)
    end

    def classes_for(gem_name)
      load_gem(gem_name).classes.sort_by(&:path)
    end

    private

    def build_loaded_gem(spec)
      loaded_gem = if File.exist?(File.join(spec.full_gem_path, ".yardoc"))
        objects = load_yard_objects(File.join(spec.full_gem_path, ".yardoc"))
        LoadedGem.new(
          name: spec.name,
          version: spec.version.to_s,
          summary: spec.summary,
          path: spec.full_gem_path,
          doc_source: :yard,
          objects: objects
        )
      elsif (rdoc_objects = load_rdoc_objects(spec))
        LoadedGem.new(
          name: spec.name,
          version: spec.version.to_s,
          summary: spec.summary,
          path: spec.full_gem_path,
          doc_source: :rdoc,
          objects: rdoc_objects,
          dynamic_lookup: ->(path) { load_rdoc_object(spec, path) }
        )
      else
        objects = load_source_objects(spec)
        LoadedGem.new(
          name: spec.name,
          version: spec.version.to_s,
          summary: spec.summary,
          path: spec.full_gem_path,
          doc_source: objects.empty? ? :none : :source_only,
          objects: objects
        )
      end

      loaded_gem
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

    def load_rdoc_objects(spec)
      return unless File.directory?(spec.doc_dir)

      response = run_shell(*ri_command(spec, "-l"))
      raise GemDocs::RegistryError.new("Failed to load ri registry: #{response[:stderr]}") unless response[:success]

      names = response[:stdout].lines.map(&:strip).reject(&:empty?)
      return if names.empty?

      names.filter_map do |name|
        load_rdoc_namespace(spec, name)
      end
    end

    def load_rdoc_namespace(spec, name)
      response = run_shell(*ri_command(spec, name))
      return unless response[:success]

      signature, docstring = parse_rdoc_output(response[:stdout])
      kind = if signature.start_with?("module ")
        :module
      else
        :class
      end

      Entry.new(
        path: name,
        name: name.split("::").last,
        kind: kind,
        visibility: :public,
        docstring: docstring,
        signature: signature.empty? ? name : signature,
        source_location: nil,
        superclass: nil,
        doc_source: :rdoc
      )
    end

    def load_rdoc_object(spec, path)
      response = run_shell(*ri_command(spec, path))
      return unless response[:success]

      signature, docstring = parse_rdoc_output(response[:stdout])
      Entry.new(
        path: path,
        name: path.split(/[#.]/).last,
        kind: rdoc_kind_for(path),
        visibility: :public,
        docstring: docstring,
        signature: signature.empty? ? path : signature,
        source_location: nil,
        superclass: nil,
        doc_source: :rdoc
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
        doc_source: :yard
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
        doc_source: :yard
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
        doc_source: :yard
      )
    end

    def load_source_objects(spec)
      ruby_files_for(spec).flat_map do |file|
        parse_source_file(file)
      end
    end

    def ruby_files_for(spec)
      Array(spec.require_paths).flat_map do |require_path|
        Dir.glob(File.join(spec.full_gem_path, require_path, "**", "*.rb"))
      end.sort
    end

    def parse_source_file(file)
      result = Prism.parse_file(file)
      stack = [ [ result.value, nil ] ]
      objects = []

      until stack.empty?
        node, namespace_path = stack.pop

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
        when Prism::DefNode
          next unless namespace_path

          method_path = if node.receiver.is_a?(Prism::SelfNode)
            "#{namespace_path}.#{node.name}"
          else
            "#{namespace_path}##{node.name}"
          end
          objects << Entry.new(
            path: method_path,
            name: node.name.to_s,
            kind: node.receiver.is_a?(Prism::SelfNode) ? :class_method : :instance_method,
            visibility: :public,
            docstring: "",
            signature: build_method_signature(namespace_path, node),
            source_location: format_source_location(file, node.location.start_line),
            superclass: nil,
            doc_source: :source_only
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
            doc_source: :source_only
          )
        else
          push_children(stack, node, namespace_path)
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
        doc_source: :source_only
      )
    end

    def build_method_signature(namespace_path, node)
      receiver_separator = node.receiver.is_a?(Prism::SelfNode) ? "." : "#"
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

    def rdoc_kind_for(path)
      return :instance_method if path.include?("#")
      return :class_method if path.match?(/\.[A-Za-z_]/)
      return :constant if path.split("::").last == path.split("::").last.upcase

      :class
    end

    def ri_command(spec, *arguments)
      [ "ri", "--no-pager", "--no-standard-docs", "-d", spec.doc_dir, *arguments ]
    end

    def run_shell(*command)
      @shell_runner.call(command)
    end

    def run_command(command)
      stdout, stderr, status = Open3.capture3(*command)
      { stdout: stdout, stderr: stderr, success: status.success? }
    end

    def push_children(stack, node, namespace_path)
      return unless node.respond_to?(:compact_child_nodes)

      node.compact_child_nodes.reverse_each do |child|
        stack << [ child, namespace_path ]
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
