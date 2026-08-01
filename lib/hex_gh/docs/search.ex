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
    version = Keyword.get(opts, :version)
    refresh = Keyword.get(opts, :refresh, false)
    examples_only = Keyword.get(opts, :include_examples_only, false)
    embedding = Keyword.get(opts, :embedding)
    limit = Keyword.get(opts, :limit, 10)

    {notices, resolved_version} = ensure_ingested(package, version, refresh, query)

    base_query = from(d in PackageDoc)

    base_query =
      if package && package != "" do
        from(d in base_query, where: d.package == ^package)
      else
        base_query
      end

    version_filter = resolved_version || version

    base_query =
      if is_binary(version_filter) and version_filter != "" and version_filter != "latest" do
        from(d in base_query, where: d.version == ^version_filter)
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
            fragment("? @@ plainto_tsquery('english', ?)", d.search_vector, ^query) or
            not is_nil(d.embedding),
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

    results =
      if results == [] do
        from(d in base_query,
          where: fragment("? @@ plainto_tsquery('english', ?)", d.search_vector, ^query),
          limit: ^limit
        )
        |> Repo.all()
      else
        results
      end

    {results, []}
  rescue
    e ->
      Logger.warning("[Docs.Search] text query failed: #{Exception.message(e)}")
      {[], ["Search query failed: #{Exception.message(e)}"]}
  end

  defp ensure_ingested(package, version, refresh, _query)
       when is_binary(package) and package != "" do
    maybe_auto_ingest(package, refresh, version)
  end

  defp ensure_ingested(_package, _version, _refresh, query) do
    notices =
      query
      |> String.downcase()
      |> String.split(~r/[^\w-]+/, trim: true)
      |> Enum.take(3)
      |> Enum.flat_map(fn term ->
        {n, _v} = maybe_auto_ingest(term, false, nil)
        n
      end)

    {notices, nil}
  end

  @ingest_timeout 15_000

  defp maybe_auto_ingest(package, refresh, version) do
    target_version = if is_binary(version) and version != "", do: version, else: "latest"

    already_ingested? =
      if target_version == "latest" do
        Repo.exists?(from(d in PackageDoc, where: d.package == ^package))
      else
        Repo.exists?(
          from(d in PackageDoc, where: d.package == ^package and d.version == ^target_version)
        )
      end

    if not refresh and already_ingested? do
      {[], nil}
    else
      Logger.info(
        "[Docs.Search] auto-ingesting docs for package: #{package} version: #{target_version}"
      )

      task =
        Task.Supervisor.async_nolink(HexGh.TaskSupervisor, fn ->
          IngestionWorker.ingest(package, target_version)
        end)

      case Task.yield(task, @ingest_timeout) || Task.shutdown(task) do
        {:ok, {:ok, count, resolved_version}} ->
          {["Docs for '#{package}' v#{resolved_version} were just indexed (#{count} docs)."],
           resolved_version}

        {:ok, {:ok, _count}} ->
          {["Docs for '#{package}' were just indexed."], nil}

        {:ok, {:error, {:no_docs, ver}}} ->
          {["No docs published for '#{package}' v#{ver} and could not detect a served version."],
           nil}

        {:ok, {:error, reason}} ->
          {["Ingestion failed for '#{package}': #{inspect(reason)}"], nil}

        nil ->
          {["Docs for '#{package}' still ingesting (large package) — try again shortly."], nil}
      end
    end
  rescue
    e ->
      Logger.warning("[Docs.Search] auto-ingest failed for #{package}: #{Exception.message(e)}")
      {["Auto-ingest failed for '#{package}': #{Exception.message(e)}"], nil}
  end
end
