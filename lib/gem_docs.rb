# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "mcp" => "MCP"
)
loader.setup

module GemDocs
  module_function

  def config(root: Dir.pwd)
    @config_cache ||= {}
    expanded_root = File.exist?(root) ? File.realpath(root) : File.expand_path(root)
    @config_cache[expanded_root] ||= Config.load(root: expanded_root)
  end

  def reset_config_cache!
    @config_cache = {}
  end
end
