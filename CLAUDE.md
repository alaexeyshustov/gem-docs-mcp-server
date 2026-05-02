# Agent Instructions

- Use TDD for new features and refactoring. Always run `bundle exec rspec` after making changes.
- Use Rubocop omakase style. Run `bundle exec rubocop -a` after editing Ruby files
- Use rbs signatures and Steep for type checking. Run `bundle exec steep check` after editing Ruby files.
- Testing Framework: RSpec, FactoryBot, VCR.

## High-level architecture

- This gem is a CLI-first Ruby project with two entrypoints: `exe/gem-docs` dispatches to `GemDocs::CLI.start`, and `exe/gem-docs-server` dispatches directly to `GemDocs::MCP::Server.start`.
- `lib/gem_docs.rb` is the bootstrap layer. It configures Zeitwerk autoloading for the gem, applies the `CLI`/`MCP` inflections, and caches `GemDocs::Config` instances by expanded project root.
- `GemDocs::CLI` builds the dry-cli registry from `COMMAND_REGISTRATIONS` in `lib/gem_docs/cli.rb`. Commands live under `GemDocs::Commands`, inherit from `GemDocs::Commands::Base`, and are expected to return process-style status codes.
- `GemDocs::Commands::Base` is the shared command surface: it exposes the current project config and converts `GemDocs::Error` subclasses into the standard stderr output, including JSON envelopes when `--format json` is used.
- `GemDocs::DocRegistry` is the core documentation loader. It caches normalized `LoadedGem` data per gem name and exposes `Entry` objects for namespaces, methods, and constants.
- Documentation lookup follows a strict fallback chain inside `GemDocs::DocRegistry`: use a gem-local `.yardoc` registry first, fall back to `ri`/RDoc data when available, and finally parse Ruby source files with Prism when structured docs are missing.
- The MCP path is intentionally isolated. The `server` CLI command lazy-loads `gem_docs/mcp/server`, and that loader only requires `fast_mcp` when the server path is actually executed.

## Key conventions

- Keep new autoloaded constants and file names Zeitwerk-compatible, and preserve the custom acronym inflections for `CLI` and `MCP`.
- When adding a new CLI command, define it under `GemDocs::Commands`, then register it in `GemDocs::CLI::COMMAND_REGISTRATIONS`; the codebase relies on lazy autoloading rather than eager `require` calls for command files.
- User-facing command failures should raise `GemDocs::Error` subclasses such as `GemNotFound`, `DocUnavailable`, `RegistryError`, or `ConfigurationError`. The CLI adapter catches those and emits the shared `{ error, message, details? }` structure on stderr.
- `.gem-docs.yml` is the only project configuration file. `GemDocs::Config` deep-merges overrides into defaults, normalizes keys to symbols, validates section types strictly, and freezes the resulting config data.
- Config objects are cached globally by expanded root path. Tests that depend on config loading patterns reset that cache with `GemDocs.reset_config_cache!` around each example.
- Preserve the registry fallback behavior and normalization layer: `DocRegistry` always converts YARD, `ri`, and Prism-derived data into `Entry` instances with a consistent shape.
- `ri` lookups are shell-backed and must keep the `--` end-of-options marker before object names so flag-like constants or namespaces are treated as lookup targets, not CLI options.
- Optional MCP support should stay optional: avoid introducing unconditional `fast_mcp` loads into the default CLI path.
- Existing specs prefer temp fixture gems plus stubbing `GemDocs::DocRegistry.gem_spec_for` over touching real installed gems, and they assert on normalized outputs rather than library internals.
