defmodule HexGh.MCP.Tools.Recall do
  @moduledoc "Search the knowledge base for relevant technical learnings."

  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response
  alias Anubis.MCP.Error
  alias HexGh.AI.Mistral
  alias HexGh.KnowledgeBase

  schema do
    field(:query, {:required, :string}, description: "Search query for the knowledge base")

    field(:kind, :string,
      description:
        "Optional filter: learning, pain_point, decision, pattern, or package_note"
    )
  end

  @impl true
  def execute(%{query: query} = params, frame) do
    kind = Map.get(params, :kind)

    with {:ok, embedding} <- Mistral.embed(query),
         results <- KnowledgeBase.search(embedding, kind: kind, limit: 5) do
      formatted =
        Enum.map(results, fn r ->
          %{
            title: r.title,
            kind: r.kind,
            content: r.content,
            metadata: r.metadata,
            similarity: Float.round(1.0 - r.distance, 4)
          }
        end)

      {:reply, Response.tool() |> Response.text(Jason.encode!(formatted)), frame}
    else
      {:error, reason} ->
        {:error, Error.execution("Search failed: #{inspect(reason)}"), frame}
    end
  end
end
