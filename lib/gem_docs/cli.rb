# frozen_string_literal: true

module GemDocs
  module CLI
    HELP_FLAGS = [ "-h", "--help", "help" ].freeze
    HELP_TEXT = <<~HELP.freeze
      gem-docs — CLI-first local gem documentation

      Usage:
        gem-docs <command> [options]

      Commands:
        list
        summary
        classes
        lookup
        search
        context
        server
    HELP

    COMMANDS = {
      "list" => "List",
      "summary" => "Summary",
      "classes" => "Classes",
      "lookup" => "Lookup",
      "search" => "Search",
      "context" => "Context",
      "server" => "Server"
    }.freeze

    module_function

    def start(arguments, out: $stdout, err: $stderr)
      return render_help(out) if arguments.empty? || HELP_FLAGS.include?(arguments.first)

      command_name = COMMANDS[arguments.first]
      return render_unknown_command(arguments.first, err: err) unless command_name

      command_class = GemDocs::Commands.const_get(command_name, false)
      command_class.new(out: out, err: err).call(arguments.drop(1))
    end

    def render_help(out)
      out.puts HELP_TEXT
      0
    end

    def render_unknown_command(command_name, err:)
      err.puts "Unknown command: #{command_name}"
      1
    end
  end
end
