# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "mcp" => "MCP"
)
loader.setup

module GemDocs
  CONFIG_CACHE_MUTEX = Mutex.new
  private_constant :CONFIG_CACHE_MUTEX

  module_function

  def config(root: Dir.pwd)
    expanded_root = File.exist?(root) ? File.realpath(root) : File.expand_path(root)

    CONFIG_CACHE_MUTEX.synchronize do
      @config_cache ||= {}
      @config_cache[expanded_root] ||= Config.load(root: expanded_root)
    end
  end

  def reset_config_cache!
    CONFIG_CACHE_MUTEX.synchronize do
      @config_cache = {}
    end
  end
end
