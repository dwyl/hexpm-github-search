defmodule HexGh.MCP.Tools.SearchGithubIssues do
  @moduledoc "Search GitHub issues and pull requests within an organization."

  use Anubis.Server.Component, type: :tool

  schema do
    field(:org, {:required, :string}, description: "GitHub organization (e.g. \"elixir-lang\")")
    field(:query, {:required, :string}, description: "Search query for issues/PRs")
  end

  @impl true
  def execute(%{org: org, query: query}, frame) do
    case HexGh.Tools.GitHub.search_issues(org, query) do
      {:ok, json} ->
        {:reply,
         Anubis.Server.Response.tool()
         |> Anubis.Server.Response.text(json), frame}

      {:error, reason} ->
        {:error, Anubis.MCP.Error.execution(to_string(reason)), frame}
    end
  end
end
