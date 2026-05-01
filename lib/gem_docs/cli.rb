# frozen_string_literal: true

require "dry/cli"

module GemDocs
  module CLI
    COMMAND_STATUS_TAG = :gem_docs_command_status
    HELP_FLAGS = [ "-h", "--help", "help" ].freeze
    COMMAND_REGISTRATIONS = {
      "classes" => "Classes",
      "context" => "Context",
      "list" => "List",
      "lookup" => "Lookup",
      "search" => "Search",
      "server" => "Server",
      "summary" => "Summary"
    }.freeze
    private_constant :COMMAND_REGISTRATIONS

    module_function

    def start(arguments, out: $stdout, err: $stderr)
      return render_help(out) if arguments.empty? || HELP_FLAGS.include?(arguments.first)

      status = catch(COMMAND_STATUS_TAG) do
        Dry::CLI.new(build_registry).call(arguments: arguments, out: out, err: err)
        0
      end

      status || 0
    rescue SystemExit => e
      e.status
    end

    def render_help(out)
      out.puts Dry::CLI::Usage.call(build_registry.get([]))
      0
    end

    def build_registry
      Module.new do
        extend Dry::CLI::Registry
      end.tap do |registry|
        COMMAND_REGISTRATIONS.each do |command_name, constant_name|
          command_class = GemDocs::Commands.const_get(constant_name, false)
          registry.register(command_name, build_command_adapter(command_class))
        end
      end
    end
    private_class_method :build_registry

    def build_command_adapter(command_class)
      Class.new(command_class) do
        desc command_class.description if command_class.description
        example command_class.examples if command_class.examples.any?

        define_method(:call) do |**kwargs|
          status = begin
            super(**kwargs)
          rescue GemDocs::Error => e
            render_command_error(e, format: kwargs.fetch(:format, "text"))
          end

          throw(COMMAND_STATUS_TAG, status)
        end
      end
    end
    private_class_method :build_command_adapter
  end
end
