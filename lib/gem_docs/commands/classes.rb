# frozen_string_literal: true

module GemDocs
  module Commands
    class Classes < Base
      desc "List documented classes and modules"
      argument :gem_name, type: :string
      option :version, desc: "Gem version"

      def call(gem_name:, version: nil, format: "text", **_kwargs)
        loaded_gem = doc_registry.load_gem(gem_name, version: version)
        out.puts GemDocs::Formatters.for(format).classes(entries: class_payloads(loaded_gem))
        0
      end

      private

      def doc_registry
        @doc_registry ||= GemDocs::DocRegistry.new
      end

      def class_payloads(loaded_gem)
        method_counts = method_counts_for(loaded_gem.objects)

        loaded_gem.classes
          .select { |entry| visible_named_entry?(entry) }
          .sort_by(&:path)
          .map do |entry|
            {
              name: entry.path,
              type: entry.kind.to_s,
              superclass: class_superclass(entry),
              summary: summary_for(entry),
              method_count: method_counts.fetch(entry.path, 0)
            }
          end
      end

      def visible_named_entry?(entry)
        entry.visibility == :public && !anonymous_entry?(entry)
      end

      def anonymous_entry?(entry)
        path = entry.path.to_s.strip
        path.empty? || path.include?("#<")
      end

      def class_superclass(entry)
        return unless entry.kind == :class
        return entry.superclass unless entry.superclass.to_s.empty?
        return if entry.path == "BasicObject"

        "Object"
      end

      def summary_for(entry)
        entry.docstring.to_s.lines.map(&:strip).reject(&:empty?).first.to_s
      end

      def method_counts_for(objects)
        objects.each_with_object(Hash.new(0)) do |object, counts|
          next unless [ :class_method, :instance_method ].include?(object.kind)
          next unless object.visibility == :public

          owner_path = method_owner_path(object.path)
          next if owner_path.nil? || owner_path.empty?

          counts[owner_path] += 1
        end
      end

      def method_owner_path(path)
        path.to_s.split(/[.#]/, 2).first
      end
    end
  end
end
