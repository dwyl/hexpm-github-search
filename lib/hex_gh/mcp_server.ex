defmodule HexGh.MCPServer do
  @moduledoc """
  Internal MCP tool registry used by the app's own agent.
  Public tools are also exposed externally via `HexGh.MCPServer.Public`.
  """

  alias HexGh.AI.Mistral
  alias HexGh.Docs.Search
  alias HexGh.Tools.GitHub
  alias HexGh.Tools.Hex
  alias HexGh.Tools.SaveMemory

  # Tools exposed to external MCP clients (Claude Code, etc.)
  @public_tools %{
    "search_github_issues" => %{
      type: "function",
      function: %{
        name: "search_github_issues",
        description: "Search GitHub issues and PRs across an organization's repositories",
        parameters: %{
          type: "object",
          properties: %{
            org: %{type: "string", description: "GitHub organization name"},
            query: %{type: "string", description: "Search query for issues/PRs"}
          },
          required: ["org", "query"]
        }
      }
    },
    "search_hex_packages" => %{
      type: "function",
      function: %{
        name: "search_hex_packages",
        description: "Search for Elixir packages on Hex.pm",
        parameters: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "Search query for packages"}
          },
          required: ["query"]
        }
      }
    },
    "search_docs" => %{
      type: "function",
      function: %{
        name: "search_docs",
        description: "Search HexDocs, typespecs, and code examples for Elixir packages",
        parameters: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "Search query for documentation or code examples"
            },
            package: %{type: "string", description: "Optional Hex package name filter"},
            include_examples_only: %{
              type: "boolean",
              description: "Optional filter to only return entries with code snippets"
            }
          },
          required: ["query"]
        }
      }
    }
  }

  # Tools only available to the internal agent
  @internal_tools %{
    "save_memory" => %{
      type: "function",
      function: %{
        name: "save_memory",
        description:
          "Save a fact or piece of knowledge to long-term memory. Optionally enrich with Hex.pm package data.",
        parameters: %{
          type: "object",
          properties: %{
            fact: %{type: "string", description: "The fact or knowledge to save"},
            package: %{
              type: "string",
              description: "Optional Hex.pm package name to auto-enrich the fact with metadata"
            }
          },
          required: ["fact"]
        }
      }
    },
    "out_of_scope" => %{
      type: "function",
      function: %{
        name: "out_of_scope",
        description:
          "Use this tool when the user's query is NOT about Elixir packages, GitHub issues, or saving knowledge. For example: greetings, general questions, time, weather, math, etc.",
        parameters: %{
          type: "object",
          properties: %{
            reason: %{type: "string", description: "Brief reason why this is out of scope"}
          },
          required: ["reason"]
        }
      }
    }
  }

  @tools Map.merge(@public_tools, @internal_tools)

  def tool_schemas, do: Map.values(@tools)
  def public_tool_schemas, do: Map.values(@public_tools)

  def call_tool("search_github_issues", %{"org" => org, "query" => query}) do
    GitHub.search_issues(org, query)
  end

  def call_tool("search_hex_packages", %{"query" => query}) do
    Hex.search_packages(query)
  end

  def call_tool("search_docs", %{"query" => query} = args) do
    package = Map.get(args, "package")
    examples_only = Map.get(args, "include_examples_only", false)

    vector =
      case Mistral.embed(query) do
        {:ok, emb} when is_list(emb) -> Pgvector.new(emb)
        _ -> nil
      end

    results =
      Search.search(query,
        package: package,
        include_examples_only: examples_only,
        embedding: vector
      )

    {:ok, results}
  end

  def call_tool("save_memory", %{"fact" => fact} = args) do
    package = Map.get(args, "package")
    SaveMemory.save(fact, package)
  end

  def call_tool("out_of_scope", %{"reason" => _reason}) do
    {:error,
     {:out_of_scope,
      "Sorry, I can't process this. I only handle Elixir package search, GitHub issue search, and saving knowledge."}}
  end

  def call_tool(name, _args) do
    {:error, "Unknown tool: #{name}"}
  end
end
