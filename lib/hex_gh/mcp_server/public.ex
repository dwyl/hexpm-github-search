defmodule HexGh.MCPServer.Public do
  @moduledoc """
  Public MCP server exposing Hex.pm and GitHub search tools
  to external clients (e.g. Claude Code) over HTTP+SSE.
  """

  # Suppress dialyzer warnings from ExMCP.Server macro-generated code
  @dialyzer :no_match

  use ExMCP.Server

  require Logger

  alias HexGh.Tools.GitHub
  alias HexGh.Tools.Hex

  deftool "search_hex_packages" do
    meta do
      name("search_hex_packages")

      description(
        "Search for Elixir packages on Hex.pm by keyword. Returns name, description, version, download counts, and URL for up to 10 matching packages."
      )
    end

    input_schema(%{
      type: "object",
      properties: %{
        query: %{type: "string", description: "Search query for packages"}
      },
      required: ["query"]
    })
  end

  deftool "search_github_issues" do
    meta do
      name("search_github_issues")

      description(
        "Search GitHub issues and PRs across an organization's repositories. Returns title, state, URL, and snippet for up to 5 matching results."
      )
    end

    input_schema(%{
      type: "object",
      properties: %{
        org: %{type: "string", description: "GitHub organization name"},
        query: %{type: "string", description: "Search query for issues/PRs"}
      },
      required: ["org", "query"]
    })
  end

  @impl true
  def handle_initialize(params, state) do
    client_info = Map.get(params, "clientInfo", %{})
    client_version = Map.get(params, "protocolVersion", "2025-03-26")

    Logger.info(
      "MCP client connected: #{inspect(client_info["name"])} v#{inspect(client_info["version"])} protocol=#{client_version}"
    )

    # Echo back the client's protocol version so version negotiation works.
    # ExMCP's MethodHandlers defaults to 2025-11-25 but only uses put_new,
    # so setting it here takes precedence.
    {:ok, %{"protocolVersion" => client_version}, state}
  end

  @impl true
  def handle_tool_call("search_hex_packages", args, state) do
    %{"query" => query} = args

    case Hex.search_packages(query) do
      {:ok, result} -> {:ok, %{content: [text(result)]}, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def handle_tool_call("search_github_issues", args, state) do
    %{"org" => org, "query" => query} = args
    # Force public-only search to prevent scanning private repos via the token
    case GitHub.search_issues(org, query <> " is:public") do
      {:ok, result} -> {:ok, %{content: [text(result)]}, state}
      {:error, reason} -> {:error, reason, state}
    end
  end
end
