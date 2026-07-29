defmodule HexGh.KnowledgeBase do
  import Ecto.Query
  alias HexGh.{Knowledge, Repo}
  alias HexGh.AI.Mistral

  def save(attrs) when is_map(attrs) do
    attrs
    |> Knowledge.changeset()
    |> Repo.insert()
  end

  def search(embedding, opts \\ []) when is_list(embedding) do
    limit = Keyword.get(opts, :limit, 5)
    kind = Keyword.get(opts, :kind)

    query =
      from(k in Knowledge,
        order_by: fragment("embedding <=> ?::vector", ^Pgvector.new(embedding)),
        limit: ^limit,
        select: %{
          id: k.id,
          kind: k.kind,
          title: k.title,
          content: k.content,
          metadata: k.metadata,
          distance: fragment("embedding <=> ?::vector", ^Pgvector.new(embedding))
        }
      )

    query =
      if kind do
        from(k in query, where: k.kind == ^kind)
      else
        query
      end

    Repo.all(query)
  end

  def list_by_kind(kind) do
    from(k in Knowledge, where: k.kind == ^kind, order_by: [desc: k.inserted_at])
    |> Repo.all()
  end

  def seed_pain_points do
    pain_points = [
      %{
        kind: "pain_point",
        title: "Caddy reverse proxy strips SSE streaming",
        content:
          "Caddy buffers HTTP responses by default, breaking Server-Sent Events (SSE) connections used by MCP StreamableHTTP transport. The MCP client sees a connection but never receives tool capabilities.",
        metadata: %{
          symptom: "MCP client connects but reports 'Capabilities: none'",
          cause: "Caddy buffers chunked/SSE responses instead of streaming them",
          fix: "Add `flush_interval -1` to the Caddy reverse_proxy directive",
          context: ["MCP", "SSE", "Caddy", "reverse proxy"]
        }
      },
      %{
        kind: "pain_point",
        title: "Bandit server requires explicit chunk writing for SSE",
        content:
          "Bandit HTTP server doesn't automatically flush response chunks like Cowboy. SSE connections hang unless you explicitly use `Plug.Conn.chunk/2` after `send_chunked/2`.",
        metadata: %{
          symptom: "SSE connections established but no events received",
          cause: "Bandit requires explicit chunk writing, unlike Cowboy",
          fix: "Use Plug.Conn.chunk/2 for each SSE event, or use Anubis's built-in SSE handling",
          context: ["Bandit", "SSE", "Plug", "streaming"]
        }
      },
      %{
        kind: "pain_point",
        title: "Docker network isolation prevents database access",
        content:
          "Services in different Docker Compose projects can't reach each other's databases by default. The hex_gh container couldn't connect to crm_postgres in another project.",
        metadata: %{
          symptom: "Database connection refused or timeout",
          cause: "Docker containers in separate compose files are on isolated networks",
          fix:
            "Use external Docker network (e.g., crm_backend) shared between compose files, reference container name as hostname",
          context: ["Docker", "PostgreSQL", "networking"]
        }
      },
      %{
        kind: "pain_point",
        title: "Boruta OAuth requires PostgreSQL-specific features",
        content:
          "Boruta OAuth library uses PostgreSQL-specific features (JSONB, gen_random_uuid(), array columns) making it incompatible with SQLite. Required adding a full Postgres setup.",
        metadata: %{
          symptom: "Migration errors with SQLite database",
          cause: "Boruta migrations use PostgreSQL-only data types and functions",
          fix:
            "Use PostgreSQL database; connect to existing Postgres instance via Docker network",
          context: ["Boruta", "OAuth", "PostgreSQL", "SQLite"]
        }
      },
      %{
        kind: "pain_point",
        title: "Argon2 password hash dollar signs break Docker env",
        content:
          "Argon2 hashes contain `$` characters which Docker Compose interprets as variable references in .env files, causing authentication to fail with mangled hashes.",
        metadata: %{
          symptom: "Admin login always fails despite correct password",
          cause: "Docker .env file interpolates $ in Argon2 hash as variable reference",
          fix: "Escape `$` as `$$` in docker-compose .env files",
          context: ["Docker", "Argon2", "authentication", "environment variables"]
        }
      },
      %{
        kind: "pain_point",
        title: "OAuth token TTL too short for CLI tools",
        content:
          "Default OAuth token TTL (1 hour) causes Claude Code MCP connections to expire during long coding sessions, requiring re-authentication.",
        metadata: %{
          symptom: "MCP connection drops after token expiry",
          cause: "Default Boruta token TTL is too short for interactive CLI usage",
          fix: "Extend token TTL to 1 year (31536000 seconds) in Boruta config",
          context: ["OAuth", "Boruta", "Claude Code", "token management"]
        }
      },
      %{
        kind: "pain_point",
        title: "MCP module naming mismatch with Anubis",
        content:
          "The original MCP server module was named HexGh.MCPServer but Anubis expected HexGh.MCP.Server. The mismatch caused silent tool registration failures.",
        metadata: %{
          symptom: "Tools registered at compile time but not available at runtime",
          cause: "Module name in supervision tree didn't match the Anubis server module",
          fix: "Ensure consistent module naming between server definition and application.ex",
          context: ["Anubis", "MCP", "module naming", "OTP"]
        }
      },
      %{
        kind: "pain_point",
        title: "runtime.exs raises crash unrelated release commands",
        content:
          "Unconditional `raise` in runtime.exs for optional service credentials crashes all release commands (migrate, eval) even when those commands don't need the service.",
        metadata: %{
          symptom: "Mix release commands crash with missing env var errors",
          cause: "runtime.exs runs for ALL release commands, not just the server",
          fix:
            "Guard raises with feature flag checks: only raise when the feature requiring the credential is enabled",
          context: ["releases", "runtime.exs", "configuration", "deployment"]
        }
      },
      %{
        kind: "pain_point",
        title: "Application.get_env in runtime.exs reads stale values",
        content:
          "Calling Application.get_env inside runtime.exs returns compile-time values, not the values being set in the same file. Config writes go to an accumulator applied after the file finishes.",
        metadata: %{
          symptom: "Config values appear as nil despite being set earlier in the same file",
          cause:
            "runtime.exs config writes to accumulator, Application.get_env reads compiled env",
          fix:
            "Store values in local variables and reference those instead of Application.get_env",
          context: ["runtime.exs", "configuration", "releases", "Config provider"]
        }
      },
      %{
        kind: "pain_point",
        title: "pgvector CREATE EXTENSION is per-database, not server-wide",
        content:
          "PostgreSQL extensions are scoped to individual databases. Running CREATE EXTENSION vector in one database (e.g. crm_reactor_prod) does not make it available in another (e.g. hex_gh). The migration fails with 'type vector does not exist' if the extension isn't enabled in the target database.",
        metadata: %{
          symptom:
            "Migration fails with 'type vector does not exist' despite extension installed in another database",
          cause: "CREATE EXTENSION is per-database in PostgreSQL, not a server-level setting",
          fix:
            "Run CREATE EXTENSION IF NOT EXISTS vector in the specific database (e.g. psql -U superuser -d hex_gh -c 'CREATE EXTENSION IF NOT EXISTS vector;')",
          context: ["PostgreSQL", "pgvector", "extensions", "migrations"]
        }
      },
      %{
        kind: "pain_point",
        title: "pgvector requires custom Postgrex types module",
        content:
          "Postgrex cannot handle the vector type by default. Without registering Pgvector.extensions() in a custom types module, queries fail with 'type vector can not be handled by the types module Postgrex.DefaultTypes'.",
        metadata: %{
          symptom:
            "Postgrex.QueryError: type 'vector' can not be handled by Postgrex.DefaultTypes",
          cause:
            "Postgrex needs custom type extensions registered to encode/decode pgvector types",
          fix:
            "Create a types module with Postgrex.Types.define(MyApp.PostgrexTypes, Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(), []) and add types: MyApp.PostgrexTypes to Repo config",
          context: ["pgvector", "Postgrex", "Ecto", "type extensions"]
        }
      },
      %{
        kind: "pain_point",
        title: "pgvector needs pgvector-enabled PostgreSQL Docker image",
        content:
          "The standard postgres Docker image does not include the pgvector extension. CREATE EXTENSION vector fails with 'could not open extension control file'. Must use the pgvector/pgvector:pgXX-bookworm image variant matching your PostgreSQL version.",
        metadata: %{
          symptom: "CREATE EXTENSION vector fails with 'could not open extension control file'",
          cause: "Standard postgres Docker image doesn't ship with pgvector extension files",
          fix:
            "Switch Docker image from postgres:XX to pgvector/pgvector:pgXX-bookworm (e.g. pgvector/pgvector:pg18-bookworm)",
          context: ["Docker", "PostgreSQL", "pgvector", "extensions"]
        }
      }
    ]

    Enum.each(pain_points, fn entry ->
      text = "#{entry.title}: #{entry.content}"

      case Mistral.embed(text) do
        {:ok, embedding} ->
          {:ok, _} = save(Map.put(entry, :embedding, embedding))
          IO.puts("Saved: #{entry.title}")

        {:error, reason} ->
          IO.puts("Failed to embed '#{entry.title}': #{inspect(reason)}")
      end
    end)
  end
end
