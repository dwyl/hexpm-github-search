defmodule HexGh.Docs.Search do
  @moduledoc """
  Provides hybrid vector and full-text search capabilities over `HexGh.PackageDoc`.
  """

  import Ecto.Query
  require Logger

  alias HexGh.Docs.IngestionWorker
  alias HexGh.PackageDoc
  alias HexGh.Repo

  @doc """
  Performs hybrid search on package docs.

  Returns `{results, notices}` where `notices` is a list of strings
  surfaced to the MCP caller (e.g. "ingesting docs for X, try again shortly").
  """
  @spec search(String.t(), keyword()) :: {[PackageDoc.t()], [String.t()]}
  def search(query, opts \\ []) when is_binary(query) do
    package = Keyword.get(opts, :package)
    examples_only = Keyword.get(opts, :include_examples_only, false)
    embedding = Keyword.get(opts, :embedding)
    limit = Keyword.get(opts, :limit, 10)

    notices = ensure_ingested(package, query)

    base_query = from(d in PackageDoc)

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

    {results, query_notices} = run_query(base_query, query, embedding, limit)
    {results, notices ++ query_notices}
  end

  defp run_query(base_query, query, vec, limit) when not is_nil(vec) do
    results =
      from(d in base_query,
        where:
          fragment("? @@ websearch_to_tsquery('english', ?)", d.search_vector, ^query) or
            fragment("? <-> ? < 0.8", d.embedding, ^vec),
        order_by: [asc: fragment("COALESCE(? <-> ?, 1.0)", d.embedding, ^vec)],
        limit: ^limit
      )
      |> Repo.all()

    {results, []}
  rescue
    e ->
      Logger.warning("[Docs.Search] hybrid query failed: #{Exception.message(e)}")
      {[], ["Search query failed: #{Exception.message(e)}"]}
  end

  defp run_query(base_query, query, _vec, limit) do
    results =
      from(d in base_query,
        where: fragment("? @@ websearch_to_tsquery('english', ?)", d.search_vector, ^query),
        limit: ^limit
      )
      |> Repo.all()

    {results, []}
  rescue
    e ->
      Logger.warning("[Docs.Search] text query failed: #{Exception.message(e)}")
      {[], ["Search query failed: #{Exception.message(e)}"]}
  end

  defp ensure_ingested(package, _query) when is_binary(package) and package != "" do
    maybe_auto_ingest(package)
  end

  defp ensure_ingested(_package, query) do
    query
    |> String.downcase()
    |> String.split(~r/[^\w-]+/, trim: true)
    |> Enum.take(3)
    |> Enum.flat_map(&maybe_auto_ingest/1)
  end

  @ingest_timeout 15_000

  defp maybe_auto_ingest(package) do
    if Repo.exists?(from(d in PackageDoc, where: d.package == ^package)) do
      []
    else
      Logger.info("[Docs.Search] auto-ingesting docs for package: #{package}")

      task =
        Task.Supervisor.async_nolink(HexGh.TaskSupervisor, fn ->
          IngestionWorker.ingest(package, "latest")
        end)

      case Task.yield(task, @ingest_timeout) || Task.shutdown(task) do
        {:ok, {:ok, _count}} ->
          ["Docs for '#{package}' were just indexed."]

        {:ok, {:error, reason}} ->
          ["Ingestion failed for '#{package}': #{inspect(reason)}"]

        nil ->
          ["Docs for '#{package}' still ingesting (large package) — try again shortly."]
      end
    end
  rescue
    e ->
      Logger.warning("[Docs.Search] auto-ingest failed for #{package}: #{Exception.message(e)}")
      ["Auto-ingest failed for '#{package}': #{Exception.message(e)}"]
  end
end
