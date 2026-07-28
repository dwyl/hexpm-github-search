defmodule HexGh.MCP.Tools.SearchGithubIssues do
  @moduledoc "Search GitHub issues and pull requests within an organization."

  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response
  alias Anubis.MCP.Error
  alias HexGh.Tools.GitHub

  schema do
    field(:org, {:required, :string}, description: "GitHub organization (e.g. \"elixir-lang\")")
    field(:query, {:required, :string}, description: "Search query for Github issues/PRs")
  end

  @impl true
  def execute(%{org: org, query: query}, frame) do
    case GitHub.search_issues(org, query) do
      {:ok, json} ->
        {:reply,
         Response.tool()
         |> Response.text(json), frame}

      {:error, reason} ->
        {:error, Error.execution(to_string(reason)), frame}
    end
  end
end
