# Local Stdio MCP Server (SQLite + FTS5 + sqlite-vec + anubis_mcp)

A lightweight, zero-external-dependency Elixir MCP server designed to run over `stdio` transport.

## Features

- **Zero Web / Zero OAuth / Zero Postgres**: Powered by SQLite (`ecto_sqlite3`) with native **FTS5 full-text search** and **sqlite-vec** for vector similarity.
- **anubis_mcp 1.14.0**: Compatible with Claude Code, Cursor, and Google Antigravity CLI (`agy`).
- **Hybrid search**: FTS5 broadens candidates, `vec_distance_cosine` re-ranks by semantic similarity — all in a single SQL query via sqlite-vec's native C layer.
- **Intelligent Knowledge Memory**: Multi-stage LLM curation pipeline (`decide`, `merge`, `append`, `discard`) powered by Mistral for deduplication and structuring.
- **HexDocs & Hex.pm Ingestion**: Auto-fetches and indexes package documentation and GitHub issues on demand using Mistral embeddings.

## Tools

| Tool | Description |
|------|-------------|
| `search_docs` | Search Hex package documentation, typespecs, and code examples |
| `search_hex_packages` | Search Hex.pm packages by keyword |
| `search_github_issues` | Search GitHub issues and pull requests within an organization |
| `remember` | Save a technical learning or pain point to the knowledge base |
| `recall` | Search the knowledge base for relevant technical learnings |

## Quickstart

### Prerequisites

- Elixir 1.15+
- [SQLite](https://www.sqlite.org/) installed
- [sqlite-vec](https://github.com/asg017/sqlite-vec) extension installed
- A [Mistral API key](https://console.mistral.ai/)

### Setup

```bash
DATABASE_PATH="priv/mcp.db" mix setup && mix compile
```

### AI Code Assistant Configuration

**Claude Code / Cursor** (`.mcp.json`):

```json
{
  "mcpServers": {
    "hex_local": {
      "command": "mix",
      "args": ["mcp.server", "--no-compile"],
      "cwd": "/absolute/path/to/stdio",
      "env": {
        "MIX_ENV": "prod",
        "MISTRAL_API_KEY": "your-key-here",
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
      }
    }
  }
}
```

**Google Antigravity** (`.mcp_config.json`):

```json
{
  "mcpServers": {
    "hex_local": {
      "command": "mix",
      "args": ["mcp.server", "--no-compile"],
      "cwd": "/absolute/path/to/stdio",
      "env": {
        "MIX_ENV": "prod",
        "MIX_QUIET": "1",
        "MISTRAL_API_KEY": "your-key-here",
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
      }
    }
  }
}
```

### Optional: Litestream replication

Replicate your SQLite database to cloud storage (S3, B2, etc.) for backup and portability.

1. Install [Litestream](https://litestream.io/install/)
2. Configure replication for `priv/mcp.db`
