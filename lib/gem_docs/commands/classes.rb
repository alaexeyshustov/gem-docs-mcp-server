# frozen_string_literal: true

module GemDocs
  module Commands
    class Classes < Base
      desc "List documented classes and modules"
      argument :gem_name, type: :string
      option :version, desc: "Gem version"

      def call(gem_name:, version: nil, format: "text", **_kwargs)
        loaded_gem = doc_registry.load_gem(gem_name, version: version)
        out.puts GemDocs::Formatters.for(format).classes(gem: gem_name, entries: class_payloads(loaded_gem))
        0
      end

      private

      def doc_registry
        @doc_registry ||= GemDocs::DocRegistry.new
      end

      def class_payloads(loaded_gem)
        loaded_gem.classes
          .select { |entry| visible_named_entry?(entry) }
          .sort_by(&:path)
          .map do |entry|
            {
              name: entry.path,
              type: entry.kind.to_s,
              superclass: class_superclass(entry),
              summary: summary_for(entry),
              method_count: method_count_for(loaded_gem, entry)
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

      def method_count_for(loaded_gem, entry)
        loaded_gem.objects.count do |object|
          next false unless [ :class_method, :instance_method ].include?(object.kind)
          next false unless object.visibility == :public

          object.path.start_with?("#{entry.path}#", "#{entry.path}.")
        end
      end
    end
  end
end
