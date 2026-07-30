defmodule HexGh.MCP.Tools.SearchDocs do
  @moduledoc "Search Hex package documentation, typespecs, and code examples."

  use Anubis.Server.Component, type: :tool

  alias Anubis.MCP.Error
  alias Anubis.Server.Response
  alias HexGh.AI.Mistral
  alias HexGh.Docs.Search

  schema do
    field(:query, {:required, :string},
      description: "Search query for Elixir package docs and code examples"
    )

    field(:package, :string,
      description: "Optional Hex package name filter (e.g., 'phoenix', 'ecto', 'req')"
    )

    field(:include_examples_only, :boolean,
      description: "Optional boolean to filter results to only entries containing code snippets"
    )
  end

  @impl true
  def execute(%{query: query} = params, frame) do
    package = Map.get(params, :package)
    examples_only = Map.get(params, :include_examples_only, false)

    vector =
      case Mistral.embed(query) do
        {:ok, emb} when is_list(emb) -> Pgvector.new(emb)
        _ -> nil
      end

    opts = [
      package: package,
      include_examples_only: examples_only,
      embedding: vector,
      limit: 10
    ]

    results = Search.search(query, opts)

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

    {:reply, Response.tool() |> Response.text(Jason.encode!(formatted)), frame}
  rescue
    e ->
      {:error, Error.execution("Search docs failed: #{Exception.message(e)}"), frame}
  end
end
