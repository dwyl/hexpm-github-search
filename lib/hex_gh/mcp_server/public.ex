defmodule HexGh.MCPServer.Public do
  @moduledoc """
  Public MCP server exposing Hex.pm, GitHub, docs, and knowledge base tools
  to external clients (e.g. Claude Code) over stdio or HTTP+SSE.
  """

  # Suppress dialyzer warnings from ExMCP.Server macro-generated code
  @dialyzer :no_match

  use ExMCP.Server

  require Logger

  alias HexGh.AI.Mistral
  alias HexGh.Docs.Search
  alias HexGh.KnowledgeBase
  alias HexGh.Tools.GitHub
  alias HexGh.Tools.Hex

  # -- Tool definitions --

  deftool "search_hex_packages" do
    meta do
      name("search_hex_packages")

      description("Search Hex.pm packages by keyword. Returns top results sorted by downloads.")
    end

    input_schema(%{
      type: "object",
      properties: %{
        query: %{type: "string", description: "Search query for Hex.pm packages"}
      },
      required: ["query"]
    })
  end

  deftool "search_github_issues" do
    meta do
      name("search_github_issues")

      description("Search GitHub issues and pull requests within an organization.")
    end

    input_schema(%{
      type: "object",
      properties: %{
        org: %{type: "string", description: "GitHub organization (e.g. \"elixir-lang\")"},
        query: %{type: "string", description: "Search query for Github issues/PRs"}
      },
      required: ["query", "org"]
    })
  end

  deftool "search_docs" do
    meta do
      name("search_docs")
      description("Search Hex package documentation, typespecs, and code examples.")
    end

    input_schema(%{
      type: "object",
      properties: %{
        query: %{
          type: "string",
          description: "Search query for Elixir package docs and code examples"
        },
        package: %{
          type: "string",
          description: "Optional Hex package name filter (e.g., 'phoenix', 'ecto', 'req')"
        },
        version: %{
          type: "string",
          description:
            "Set to 'latest' to force re-ingestion of fresh docs. Omit to use cached docs."
        },
        include_examples_only: %{
          type: "boolean",
          description:
            "Optional boolean to filter results to only entries containing code snippets"
        }
      },
      required: ["query"]
    })
  end

  deftool "remember" do
    meta do
      name("remember")
      description("Save a technical learning or pain point to the knowledge base.")
    end

    input_schema(%{
      type: "object",
      properties: %{
        text: %{
          type: "string",
          description:
            "Technical learning, pain point, pattern, or architectural decision to save to project memory. " <>
              "Synthesize the text to include: 1) What occurred / symptom, 2) Root cause, 3) Solution / fix, " <>
              "4) Technologies/stack involved, and 5) Package name, version constraints (e.g. 'pgvector ~> 0.3'), " <>
              "and GitHub repo if applicable. " <>
              "Example: 'In anubis_mcp (jfim/anubis-mcp, branch non-upstreamed-fixes), the SSE keepalive " <>
              "defaults to 5s which causes timeouts behind Caddy. Fixed by adding flush_interval -1 to Caddyfile.'"
        }
      },
      required: ["text"]
    })
  end

  deftool "recall" do
    meta do
      name("recall")
      description("Search the knowledge base for relevant technical learnings.")
    end

    input_schema(%{
      type: "object",
      properties: %{
        query: %{type: "string", description: "Search query for the knowledge base"},
        kind: %{
          type: "string",
          description: "Optional filter: learning, pain_point, decision, pattern, or package_note"
        },
        domain: %{
          type: "string",
          description: "Optional domain filter: deploy, config, code, or debug"
        },
        stack: %{
          type: "string",
          description:
            "Optional technology tag filter (e.g. 'caddy', 'postgres', 'bandit', 'elixir')"
        },
        package: %{
          type: "string",
          description:
            "Optional Hex.pm package name filter (e.g. 'phoenix', 'boruta', 'anubis_mcp')"
        }
      },
      required: ["query"]
    })
  end

  # -- Callbacks --

  @impl true
  def handle_initialize(params, state) do
    client_info = Map.get(params, "clientInfo", %{})
    client_version = Map.get(params, "protocolVersion", "2025-03-26")

    Logger.info(
      "MCP client connected: #{inspect(client_info["name"])} v#{inspect(client_info["version"])} protocol=#{client_version}"
    )

    {:ok, %{"protocolVersion" => client_version}, state}
  end

  @impl true
  def handle_tool_call("search_hex_packages", %{"query" => query}, state) do
    case Hex.search_packages(query) do
      {:ok, result} -> {:ok, %{content: [text(result)]}, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def handle_tool_call("search_github_issues", %{"org" => org, "query" => query}, state) do
    case GitHub.search_issues(org, query <> " is:public") do
      {:ok, result} -> {:ok, %{content: [text(result)]}, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def handle_tool_call("search_docs", args, state) do
    query = args["query"]
    package = args["package"]
    version = args["version"]
    examples_only = args["include_examples_only"] || false

    vector =
      case Mistral.embed(query) do
        {:ok, emb} when is_list(emb) -> Pgvector.new(emb)
        _ -> nil
      end

    opts = [
      package: package,
      version: version,
      refresh: version == "latest",
      include_examples_only: examples_only,
      embedding: vector,
      limit: 10
    ]

    {results, notices} = Search.search(query, opts)

    formatted =
      Enum.map(results, fn r ->
        %{
          id: r.id,
          package: r.package,
          version: r.version,
          doc_type: r.doc_type,
          module: r.module,
          function: r.function,
          signature: r.signature,
          content: r.content,
          code_snippet: r.code_snippet,
          hexdocs_url: r.hexdocs_url
        }
      end)

    payload =
      if notices == [], do: %{results: formatted}, else: %{results: formatted, notices: notices}

    {:ok, %{content: [text(Jason.encode!(payload))]}, state}
  rescue
    e ->
      {:error, "Search docs failed: #{Exception.message(e)}", state}
  end

  @impl true
  def handle_tool_call("remember", %{"text" => text}, state) do
    Task.Supervisor.start_child(HexGh.TaskSupervisor, fn ->
      HexGh.MCP.Tools.Remember.process(text)
    end)

    {:ok, %{content: [text(Jason.encode!(%{accepted: true, status: "processing"}))]}, state}
  end

  @impl true
  def handle_tool_call("recall", args, state) do
    query = args["query"]

    opts =
      [
        limit: 5,
        query: query,
        kind: args["kind"],
        domain: args["domain"],
        stack: args["stack"],
        package: args["package"]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Mistral.embed(query) do
      {:ok, embedding} ->
        results = KnowledgeBase.search(embedding, opts)

        formatted =
          Enum.map(results, fn r ->
            %{
              id: r.id,
              title: r.title,
              kind: r.kind,
              content: r.content,
              metadata: r.metadata,
              similarity: Float.round(1.0 - r.distance, 4)
            }
          end)

        {:ok, %{content: [text(Jason.encode!(formatted))]}, state}

      {:error, reason} ->
        {:error, "Search failed: #{inspect(reason)}", state}
    end
  end
end
