defmodule HexGh.Docs.Search do
  @moduledoc """
  Provides hybrid vector and full-text search capabilities over `HexGh.PackageDoc`.
  """

  import Ecto.Query
  alias HexGh.PackageDoc
  alias HexGh.Repo

  @doc """
  Performs hybrid search on package docs using vector cosine distance and tsvector text matching.
  """
  @spec search(String.t(), keyword()) :: [PackageDoc.t()]
  def search(query, opts \\ []) when is_binary(query) do
    package = Keyword.get(opts, :package)
    examples_only = Keyword.get(opts, :include_examples_only, false)
    embedding = Keyword.get(opts, :embedding)
    limit = Keyword.get(opts, :limit, 10)

    base_query = from(d in PackageDoc)

    if package && package != "" do
      maybe_auto_ingest(package)
    else
      query
      |> String.downcase()
      |> String.split(~r/[^\w-]+/, trim: true)
      |> Enum.take(3)
      |> Enum.each(&maybe_auto_ingest/1)
    end

    base_query =
      if package && package != "" do
        from(d in base_query, where: d.package == ^package)
      else
        base_query
      end

    base_query =
      if examples_only do
        from(d in base_query, where: not is_nil(d.code_snippet) and d.code_snippet != "")
      else
        base_query
      end

    try do
      case embedding do
        vec when not is_nil(vec) ->
          from(d in base_query,
            where:
              fragment("? @@ websearch_to_tsquery('english', ?)", d.search_vector, ^query) or
                not is_nil(d.embedding),
            order_by: [
              asc: fragment("COALESCE(? <-> ?, 1.0)", d.embedding, ^vec)
            ],
            limit: ^limit
          )
          |> Repo.all()

        _ ->
          from(d in base_query,
            where: fragment("? @@ websearch_to_tsquery('english', ?)", d.search_vector, ^query),
            limit: ^limit
          )
          |> Repo.all()
      end
    rescue
      _ -> []
    end
  end

  defp maybe_auto_ingest(package) do
    try do
      unless Repo.exists?(from(d in PackageDoc, where: d.package == ^package)) do
        HexGh.Docs.IngestionWorker.ingest(package, "latest")
      end
    rescue
      _ -> :ok
    end
  end
end
