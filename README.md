# gem-docs

CLI-first gem documentation lookup for local Ruby projects, with an optional MCP server wrapper.

## CLI

```bash
bundle exec exe/gem-docs list
bundle exec exe/gem-docs summary faraday --format json
bundle exec exe/gem-docs lookup Faraday::Connection#get --gem faraday
bundle exec exe/gem-docs search Widget --scope classes
```

## MCP server

The MCP path is optional and only loads `fast-mcp` when you start the server.

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
