defmodule HexGh.KnowledgeBase do
  @moduledoc """
  Methods `save/1`, 'update/2`, 'search/2`, `list_by_kind/1`.
  """

  import Ecto.Query
  alias HexGh.AI.Mistral
  alias HexGh.{Knowledge, Repo}

  def save(attrs) when is_map(attrs) do
    attrs
    |> Knowledge.changeset()
    |> Repo.insert()
  end

  def update(id, attrs) when is_integer(id) and is_map(attrs) do
    case Repo.get(Knowledge, id) do
      nil -> {:error, :not_found}
      entry -> entry |> Knowledge.changeset(attrs) |> Repo.update()
    end
  end

  def deprecate(id, reason \\ nil) when is_integer(id) do
    case Repo.get(Knowledge, id) do
      nil ->
        {:error, :not_found}

      entry ->
        meta =
          Map.put(
            entry.metadata || %{},
            "deprecated_reason",
            reason || "Marked as outdated by user/curator"
          )

        entry
        |> Knowledge.changeset(%{outdated: true, metadata: meta})
        |> Repo.update()
    end
  end

  def search(embedding, opts \\ []) when is_list(embedding) do
    query_text = Keyword.get(opts, :query) || Keyword.get(opts, :query_text)

    if query_text && is_binary(query_text) && query_text != "" do
      search_hybrid(query_text, embedding, opts)
    else
      search_vector(embedding, opts)
    end
  end

  def search_hybrid(query_text, embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    kind = Keyword.get(opts, :kind)
    domain = Keyword.get(opts, :domain)
    stack = Keyword.get(opts, :stack)
    package = Keyword.get(opts, :package)

    sql = """
    WITH pre_filtered AS (
      SELECT id, title, kind, content, metadata, updated_at, embedding, search_vector
      FROM knowledge
      WHERE (outdated = false)
        AND ($1::text IS NULL OR kind = $1)
        AND ($2::text IS NULL OR metadata->>'domain' = $2)
        AND ($3::text IS NULL OR metadata->>'package' = $3)
        AND ($4::text IS NULL OR metadata->'stack' @> jsonb_build_array($4::text))
    ),
    vector_candidates AS (
      SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> $5::vector) AS vec_rank
      FROM pre_filtered
      ORDER BY embedding <=> $5::vector
      LIMIT 20
    ),
    text_candidates AS (
      SELECT id, ROW_NUMBER() OVER (ORDER BY ts_rank_cd(search_vector, websearch_to_tsquery('english', $6)) DESC) AS text_rank
      FROM pre_filtered
      WHERE search_vector @@ websearch_to_tsquery('english', $6)
      LIMIT 20
    ),
    candidate_pool AS (
      SELECT id FROM vector_candidates
      UNION
      SELECT id FROM text_candidates
    )
    SELECT k.id, k.title, k.kind, k.content, k.metadata, k.updated_at,
           (k.embedding <=> $5::vector) AS distance,
           ((COALESCE(1.0 / (60.0 + v.vec_rank), 0.0) + COALESCE(1.0 / (60.0 + t.text_rank), 0.0)) *
            POWER(0.995, GREATEST(0.0, EXTRACT(DAY FROM (NOW() - k.updated_at))))) AS rrf_score
    FROM candidate_pool c
    JOIN knowledge k ON k.id = c.id
    LEFT JOIN vector_candidates v ON v.id = c.id
    LEFT JOIN text_candidates t ON t.id = c.id
    ORDER BY rrf_score DESC
    LIMIT $7;
    """

    params = [
      kind,
      domain,
      package,
      stack,
      Pgvector.new(embedding),
      query_text,
      limit
    ]

    case Repo.query(sql, params) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          map = Enum.zip(columns, row) |> Map.new()

          %{
            id: map["id"],
            title: map["title"],
            kind: map["kind"],
            content: map["content"],
            metadata: map["metadata"] || %{},
            updated_at: map["updated_at"],
            distance: map["distance"] || 0.0
          }
        end)

      {:error, _reason} ->
        # Fallback to vector search if ts_vector column is not yet present
        search_vector(embedding, opts)
    end
  end

  @doc "Pure vector cosine similarity search. Use `search/2` for hybrid (vector + full-text)."
  def search_vector(embedding, opts \\ []) when is_list(embedding) do
    limit = Keyword.get(opts, :limit, 5)
    kind = Keyword.get(opts, :kind)
    domain = Keyword.get(opts, :domain)
    stack = Keyword.get(opts, :stack)
    package = Keyword.get(opts, :package)

    query = from(k in Knowledge, where: k.outdated == false)

    query = if kind, do: from(k in query, where: k.kind == ^kind), else: query

    query =
      if domain,
        do: from(k in query, where: fragment("?->>'domain' = ?", k.metadata, ^domain)),
        else: query

    query =
      if package,
        do: from(k in query, where: fragment("?->>'package' = ?", k.metadata, ^package)),
        else: query

    query =
      if stack do
        from(k in query,
          where: fragment("?->'stack' @> jsonb_build_array(?::text)", k.metadata, ^stack)
        )
      else
        query
      end

    query =
      from(k in query,
        order_by:
          fragment(
            "(1.0 - (embedding <=> ?::vector)) * POWER(0.995, GREATEST(0.0, EXTRACT(DAY FROM (NOW() - ?)))) DESC",
            ^Pgvector.new(embedding),
            k.updated_at
          ),
        limit: ^limit,
        select: %{
          id: k.id,
          kind: k.kind,
          title: k.title,
          content: k.content,
          metadata: k.metadata,
          updated_at: k.updated_at,
          distance: fragment("embedding <=> ?::vector", ^Pgvector.new(embedding))
        }
      )

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
          domain: "deploy",
          stack: ["caddy", "mcp", "sse"],
          symptom: "MCP client connects but reports 'Capabilities: none'",
          cause: "Caddy buffers chunked/SSE responses instead of streaming them",
          fix: "Add `flush_interval -1` to the Caddy reverse_proxy directive"
        }
      },
      %{
        kind: "pain_point",
        title: "Bandit server requires explicit chunk writing for SSE",
        content:
          "Bandit HTTP server doesn't automatically flush response chunks like Cowboy. SSE connections hang unless you explicitly use `Plug.Conn.chunk/2` after `send_chunked/2`.",
        metadata: %{
          domain: "code",
          stack: ["elixir", "bandit", "sse", "plug"],
          package: "bandit",
          symptom: "SSE connections established but no events received",
          cause: "Bandit requires explicit chunk writing, unlike Cowboy",
          fix: "Use Plug.Conn.chunk/2 for each SSE event, or use Anubis's built-in SSE handling"
        }
      },
      %{
        kind: "pain_point",
        title: "Docker network isolation prevents database access",
        content:
          "Services in different Docker Compose projects can't reach each other's databases by default. The hex_gh container couldn't connect to crm_postgres in another project.",
        metadata: %{
          domain: "deploy",
          stack: ["docker", "postgres"],
          symptom: "Database connection refused or timeout",
          cause: "Docker containers in separate compose files are on isolated networks",
          fix:
            "Use external Docker network (e.g., crm_backend) shared between compose files, reference container name as hostname"
        }
      },
      %{
        kind: "pain_point",
        title: "Boruta OAuth requires PostgreSQL-specific features",
        content:
          "Boruta OAuth library uses PostgreSQL-specific features (JSONB, gen_random_uuid(), array columns) making it incompatible with SQLite. Required adding a full Postgres setup.",
        metadata: %{
          domain: "config",
          stack: ["elixir", "postgres", "sqlite"],
          package: "boruta",
          package_version: "~> 3.0.0-beta.4",
          symptom: "Migration errors with SQLite database",
          cause: "Boruta migrations use PostgreSQL-only data types and functions",
          fix: "Use PostgreSQL database; connect to existing Postgres instance via Docker network"
        }
      },
      %{
        kind: "pain_point",
        title: "Argon2 password hash dollar signs break Docker env",
        content:
          "Argon2 hashes contain `$` characters which Docker Compose interprets as variable references in .env files, causing authentication to fail with mangled hashes.",
        metadata: %{
          domain: "deploy",
          stack: ["docker", "elixir"],
          package: "argon2_elixir",
          symptom: "Admin login always fails despite correct password",
          cause: "Docker .env file interpolates $ in Argon2 hash as variable reference",
          fix: "Escape `$` as `$$` in docker-compose .env files"
        }
      },
      %{
        kind: "pain_point",
        title: "OAuth token TTL too short for CLI tools",
        content:
          "Default OAuth token TTL (1 hour) causes Claude Code MCP connections to expire during long coding sessions, requiring re-authentication.",
        metadata: %{
          domain: "config",
          stack: ["elixir", "mcp", "boruta"],
          package: "boruta",
          symptom: "MCP connection drops after token expiry",
          cause: "Default Boruta token TTL is too short for interactive CLI usage",
          fix: "Extend token TTL to 1 year (31536000 seconds) in Boruta config"
        }
      },
      %{
        kind: "pain_point",
        title: "MCP module naming mismatch with Anubis",
        content:
          "The original MCP server module was named HexGh.MCPServer but Anubis expected HexGh.MCP.Server. The mismatch caused silent tool registration failures.",
        metadata: %{
          domain: "code",
          stack: ["elixir", "mcp", "otp"],
          package: "anubis_mcp",
          repo: "jfim/anubis-mcp",
          symptom: "Tools registered at compile time but not available at runtime",
          cause: "Module name in supervision tree didn't match the Anubis server module",
          fix: "Ensure consistent module naming between server definition and application.ex"
        }
      },
      %{
        kind: "pain_point",
        title: "runtime.exs raises crash unrelated release commands",
        content:
          "Unconditional `raise` in runtime.exs for optional service credentials crashes all release commands (migrate, eval) even when those commands don't need the service.",
        metadata: %{
          domain: "config",
          stack: ["elixir", "phoenix"],
          symptom: "Mix release commands crash with missing env var errors",
          cause: "runtime.exs runs for ALL release commands, not just the server",
          fix:
            "Guard raises with feature flag checks: only raise when the feature requiring the credential is enabled"
        }
      },
      %{
        kind: "pain_point",
        title: "Application.get_env in runtime.exs reads stale values",
        content:
          "Calling Application.get_env inside runtime.exs returns compile-time values, not the values being set in the same file. Config writes go to an accumulator applied after the file finishes.",
        metadata: %{
          domain: "config",
          stack: ["elixir"],
          symptom: "Config values appear as nil despite being set earlier in the same file",
          cause:
            "runtime.exs config writes to accumulator, Application.get_env reads compiled env",
          fix:
            "Store values in local variables and reference those instead of Application.get_env"
        }
      },
      %{
        kind: "pain_point",
        title: "pgvector CREATE EXTENSION is per-database, not server-wide",
        content:
          "PostgreSQL extensions are scoped to individual databases. Running CREATE EXTENSION vector in one database (e.g. crm_reactor_prod) does not make it available in another (e.g. hex_gh). The migration fails with 'type vector does not exist' if the extension isn't enabled in the target database.",
        metadata: %{
          domain: "deploy",
          stack: ["postgres", "pgvector"],
          package: "pgvector",
          symptom:
            "Migration fails with 'type vector does not exist' despite extension installed in another database",
          cause: "CREATE EXTENSION is per-database in PostgreSQL, not a server-level setting",
          fix:
            "Run CREATE EXTENSION IF NOT EXISTS vector in the specific database (e.g. psql -U superuser -d hex_gh -c 'CREATE EXTENSION IF NOT EXISTS vector;')"
        }
      },
      %{
        kind: "pain_point",
        title: "pgvector requires custom Postgrex types module",
        content:
          "Postgrex cannot handle the vector type by default. Without registering Pgvector.extensions() in a custom types module, queries fail with 'type vector can not be handled by the types module Postgrex.DefaultTypes'.",
        metadata: %{
          domain: "config",
          stack: ["elixir", "postgres", "postgrex", "ecto"],
          package: "pgvector",
          package_version: "~> 0.3",
          symptom:
            "Postgrex.QueryError: type 'vector' can not be handled by Postgrex.DefaultTypes",
          cause:
            "Postgrex needs custom type extensions registered to encode/decode pgvector types",
          fix:
            "Create a types module with Postgrex.Types.define(MyApp.PostgrexTypes, Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions(), []) and add types: MyApp.PostgrexTypes to Repo config"
        }
      },
      %{
        kind: "pain_point",
        title: "pgvector needs pgvector-enabled PostgreSQL Docker image",
        content:
          "The standard postgres Docker image does not include the pgvector extension. CREATE EXTENSION vector fails with 'could not open extension control file'. Must use the pgvector/pgvector:pgXX-bookworm image variant matching your PostgreSQL version.",
        metadata: %{
          domain: "deploy",
          stack: ["docker", "postgres", "pgvector"],
          symptom: "CREATE EXTENSION vector fails with 'could not open extension control file'",
          cause: "Standard postgres Docker image doesn't ship with pgvector extension files",
          fix:
            "Switch Docker image from postgres:XX to pgvector/pgvector:pgXX-bookworm (e.g. pgvector/pgvector:pg18-bookworm)"
        }
      }
    ]

    Enum.each(pain_points, &seed_entry/1)
  end

  defp seed_entry(entry) do
    if Repo.exists?(from(k in Knowledge, where: k.title == ^entry.title)) do
      IO.puts("Skipped (exists): #{entry.title}")
    else
      case Mistral.embed("#{entry.title}: #{entry.content}") do
        {:ok, embedding} ->
          {:ok, _} = save(Map.put(entry, :embedding, embedding))
          IO.puts("Saved: #{entry.title}")

        {:error, reason} ->
          IO.puts("Failed to embed '#{entry.title}': #{inspect(reason)}")
      end
    end
  end
end
