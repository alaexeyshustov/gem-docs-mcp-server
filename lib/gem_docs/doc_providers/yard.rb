# frozen_string_literal: true

require "yard"

module GemDocs
  module DocProviders
    class Yard
      YARD_MUTEX = Mutex.new
      private_constant :YARD_MUTEX

      def initialize(loaded_gem_builder:)
        @loaded_gem_builder = loaded_gem_builder
      end

      def available?(spec)
        File.exist?(yardoc_path_for(spec))
      end

      def load(spec)
        @loaded_gem_builder.call(spec, load_objects(yardoc_path_for(spec)), :yard)
      end

      private

      def yardoc_path_for(spec)
        File.join(spec.full_gem_path, ".yardoc")
      end

      def load_objects(yardoc)
        YARD_MUTEX.synchronize do
          previous_yardoc = YARD::Registry.yardoc_file
          YARD::Registry.clear
          YARD::Registry.load!(yardoc)

          objects = [] # : Array[GemDocs::DocRegistry::Entry]
          queue = YARD::Registry.root.children.reverse

          until queue.empty?
            object = queue.pop

            case object
            when YARD::CodeObjects::ClassObject, YARD::CodeObjects::ModuleObject
              objects << build_namespace_entry(object)
              queue.concat(object.constants(inherited: false).reverse)
              queue.concat(object.meths(inherited: false).reverse)
              queue.concat(object.children.grep(YARD::CodeObjects::NamespaceObject).reverse)
            when YARD::CodeObjects::MethodObject
              objects << build_method_entry(object)
            when YARD::CodeObjects::ConstantObject
              objects << build_constant_entry(object)
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

      def build_namespace_entry(object)
        GemDocs::DocRegistry::Entry.new(
          path: object.path,
          name: object.name.to_s,
          kind: object.is_a?(YARD::CodeObjects::ClassObject) ? :class : :module,
          visibility: object.visibility || :public,
          docstring: object.docstring.to_s,
          signature: object.path,
          source_location: source_location_for(object),
          superclass: superclass_for(object),
          doc_source: :yard,
          tags: tags_for(object),
          aliases: aliases_for(object)
        )
      end

      def build_method_entry(object)
        GemDocs::DocRegistry::Entry.new(
          path: object.path,
          name: object.name.to_s,
          kind: object.scope == :class ? :class_method : :instance_method,
          visibility: object.visibility || :public,
          docstring: object.docstring.to_s,
          signature: object.signature || object.path,
          source_location: source_location_for(object),
          superclass: nil,
          doc_source: :yard,
          tags: tags_for(object),
          aliases: aliases_for(object)
        )
      end

      def build_constant_entry(object)
        GemDocs::DocRegistry::Entry.new(
          path: object.path,
          name: object.name.to_s,
          kind: :constant,
          visibility: object.visibility || :public,
          docstring: object.docstring.to_s,
          signature: object.path,
          source_location: source_location_for(object),
          superclass: nil,
          doc_source: :yard,
          tags: tags_for(object),
          aliases: aliases_for(object)
        )
      end

      def source_location_for(object)
        return unless object.file && object.line

        "#{object.file}:#{object.line}"
      end

      def superclass_for(object)
        return unless object.is_a?(YARD::CodeObjects::ClassObject)

        superclass = object.superclass
        return unless superclass

        superclass.respond_to?(:path) ? superclass.path : superclass.to_s
      end

      def tags_for(object)
        return {} unless object.respond_to?(:tags)

        # @type var grouped_tags: Hash[Symbol, untyped]
        grouped_tags = {}
        object.tags.each do |tag|
          normalized = normalize_tag(tag)
          next if normalized.nil?

          grouped_tags[tag.tag_name.to_sym] ||= []
          grouped_tags[tag.tag_name.to_sym] << normalized
        end

        grouped_tags
      end

      def normalize_tag(tag)
        return tag.text.to_s.strip if tag.tag_name == "example"

        # @type var payload: Hash[Symbol, untyped]
        payload = {}
        payload[:name] = tag.name if tag.respond_to?(:name) && tag.name
        payload[:types] = Array(tag.types).map do |type|
          # @type var type: untyped
          type.to_s
        end if tag.respond_to?(:types)
        payload[:text] = tag.text.to_s.strip
        payload
      end

      def aliases_for(object)
        return [] unless object.respond_to?(:aliases)

        Array(object.aliases).filter_map do |alias_object|
          # @type var alias_object: untyped
          alias_object.respond_to?(:path) ? alias_object.path : alias_object.to_s
        end
      end
    end
  end
end
