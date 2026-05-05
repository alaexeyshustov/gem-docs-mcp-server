# gem-docs

CLI-first gem documentation lookup for local Ruby projects, with an optional MCP server wrapper.

## Persistent cache

`gem-docs` stores normalized documentation artifacts in a local SQLite database at `.gem-docs/cache.sqlite3`.
The cache keeps source-derived artifacts and future compressed artifacts in separate rows keyed by gem name, gem version, and lookup target.
Entries are invalidated automatically when the gem contents change or when the cache schema/artifact version changes.

## Offline compression for non-obvious knowledge

The cache now persists per-entry source artifacts alongside the whole-gem snapshot so an offline preprocessing pass can read normalized lookup payloads from SQLite and write compressed knowledge back into the same database.

`GemDocs::Compression::Pipeline` is the offline entrypoint. It accepts an injected compressor callable, reads the current source artifacts for a gem/version from the cache, and stores compressed rows under the same gem/version/lookup-target key space using `artifact_kind = compressed`.

### What counts as non-obvious knowledge

Keep only gem-specific details that a strong model is unlikely to infer from general Ruby knowledge:

- surprising behavior
- caveats and footguns
- conventions that are specific to the gem
- edge cases and fallback rules
- version-scoped behavior changes

If a source artifact contains only obvious API surface information, the compressor should return `status: "insufficient"` so runtime lookup falls back to the raw source-derived artifact.

### Prompt and schema

The pipeline ships a documented prompt definition in `GemDocs::Compression::Pipeline::NON_OBVIOUS_KNOWLEDGE_DEFINITION` and validates the compressor response against the `OUTPUT_SCHEMA` shape before adding cache metadata:

```json
{
  "status": "ready | insufficient",
  "reason": "optional explanation when compression is insufficient",
  "insights": [
    {
      "title": "short finding",
      "detail": "non-obvious gem-specific behavior",
      "categories": ["behavior", "edge_case"],
      "version_scope": "optional version note"
    }
  ]
}
```

Each compressed payload also stores:

- `prompt_version`
- `source_artifact.lookup_target`
- `source_artifact.artifact_kind`
- `source_artifact.artifact_version`
- `source_artifact.invalidation_key`
- `source_artifact.payload_digest`

That linkage lets runtime lookup distinguish compressed insight from raw documentation and safely fall back when compressed knowledge is missing or insufficient.

### Evaluation approach

Evaluate compression on a small representative gem set (for example: an HTTP client, a Rails-adjacent utility, and a source-only gem fixture) and compare:

1. the raw source-derived artifact
2. the compressed insights
3. the runtime lookup result after fallback rules are applied

A compression pass is acceptable only when the compressed payload preserves the important gem-specific caveats and lookup still returns raw/source-derived documentation whenever compression is absent or marked insufficient.

## CLI

```bash
bundle exec exe/gem-docs list
bundle exec exe/gem-docs summary faraday --format json
bundle exec exe/gem-docs lookup Faraday::Connection#get --gem faraday
bundle exec exe/gem-docs search Widget --scope classes
```

## MCP server

The MCP path is optional and only loads `fast-mcp` when you start the server.

Install the optional dependency before using the server entrypoints:

```ruby
gem "fast-mcp"
```

Then run `bundle install`.

### STDIO mode

```bash
bundle exec exe/gem-docs server
# or
bundle exec exe/gem-docs-server
```

### HTTP mode

```bash
bundle exec exe/gem-docs server --mode http --port 6040
bundle exec exe/gem-docs server --mode http --port 6040 --bind-all
```

HTTP mode serves MCP endpoints under `/mcp`.

### Exposed MCP tools

- `list`
- `summary`
- `classes`
- `lookup`
- `search`

Each tool delegates to the same command layer as the CLI and returns the CLI JSON payload as MCP tool output.
