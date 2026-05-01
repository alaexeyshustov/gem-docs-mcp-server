# frozen_string_literal: true

require "dry/cli"

module GemDocs
  module CLI
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

      Dry::CLI.new(build_registry).call(arguments: arguments, out: out, err: err) || 0
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
          registry.register(command_name, GemDocs::Commands.const_get(constant_name, false))
        end
      end
    end
    private_class_method :build_registry
  end
end
