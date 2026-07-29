defmodule HexGh.MCP.Tools.Recall do
  @moduledoc "Search the knowledge base for relevant technical learnings."

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexGh.AI.Mistral
  alias HexGh.KnowledgeBase

  schema do
    field(:query, {:required, :string}, description: "Search query for the knowledge base")

    field(:kind, :string,
      description: "Optional filter: learning, pain_point, decision, pattern, or package_note"
    )

    field(:domain, :string, description: "Optional domain filter: deploy, config, code, or debug")

    field(:stack, :string,
      description: "Optional technology tag filter (e.g. 'caddy', 'postgres', 'bandit', 'elixir')"
    )

    field(:package, :string,
      description: "Optional Hex.pm package name filter (e.g. 'phoenix', 'boruta', 'anubis_mcp')"
    )
  end

  @impl true
  def execute(%{query: query} = params, frame) do
    opts =
      [
        limit: 5,
        query: query,
        kind: Map.get(params, :kind),
        domain: Map.get(params, :domain),
        stack: Map.get(params, :stack),
        package: Map.get(params, :package)
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

        {:reply, Response.tool() |> Response.text(Jason.encode!(formatted)), frame}

      {:error, reason} ->
        {:error, Error.execution("Search failed: #{inspect(reason)}"), frame}
    end
  end
end
