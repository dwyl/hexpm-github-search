defmodule HexGh.Docs.IngestionWorker do
  @moduledoc """
  Ingests documentation and code examples from HexDocs for Elixir packages.
  Parses ExDoc search_data index, extracts module/function docs, extracts code blocks,
  generates embeddings via `HexGh.AI.Mistral`, and stores them in `package_docs`.
  """

  import Ecto.Query
  require Logger

  alias HexGh.AI.Mistral
  alias HexGh.PackageDoc
  alias HexGh.Repo

  @doc """
  Ingests docs for a given package and version.
  Defaults to "latest" which looks up the latest release from hex.pm.
  """
  @spec ingest(String.t(), String.t()) :: {:ok, integer()} | {:error, term()}
  def ingest(package, version \\ "latest") when is_binary(package) do
    with {:ok, resolved_version} <- resolve_version(package, version),
         {:ok, search_data} <- fetch_search_data(package, resolved_version) do
      items = Map.get(search_data, "items", [])

      docs =
        items
        |> Enum.map(&build_doc_item(package, resolved_version, &1))
        |> Enum.reject(&is_nil/1)

      docs_with_embeddings = Enum.map(docs, &attach_embedding/1)
      save_docs(docs_with_embeddings, package, resolved_version)
    end
  end

  defp save_docs(docs_with_embeddings, package, version) do
    Repo.transaction(fn ->
      from(d in PackageDoc, where: d.package == ^package and d.version == ^version)
      |> Repo.delete_all()

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      entries =
        Enum.map(docs_with_embeddings, fn doc ->
          doc
          |> Map.put(:inserted_at, now)
          |> Map.put(:updated_at, now)
        end)

      if entries != [] do
        {count, _} = Repo.insert_all(PackageDoc, entries)
        count
      else
        0
      end
    end)
  end

  defp resolve_version(package, "latest") do
    url = "https://hex.pm/api/packages/#{package}"

    case Req.get(url, headers: [{"user-agent", "hex_gh/1.0"}]) do
      {:ok, %{status: 200, body: %{"releases" => [%{"version" => ver} | _]}}} ->
        {:ok, ver}

      {:ok, %{status: 404}} ->
        {:error, :package_not_found}

      error ->
        Logger.error("Failed to resolve version for package #{package}: #{inspect(error)}")
        {:error, :version_resolution_failed}
    end
  end

  defp resolve_version(_package, version), do: {:ok, version}

  defp fetch_search_data(package, version) do
    primary_url = "https://hexdocs.pm/#{package}/#{version}/search_data.js"

    case Req.get(primary_url, headers: [{"user-agent", "hex_gh/1.0"}]) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        parse_search_data_js(body)

      _ ->
        fetch_search_data_fallback(package, version)
    end
  end

  defp fetch_search_data_fallback(package, version) do
    index_url = "https://hexdocs.pm/#{package}/#{version}/"

    with {:ok, %{status: 200, body: html}} when is_binary(html) <-
           Req.get(index_url, headers: [{"user-agent", "hex_gh/1.0"}]),
         [_, search_file] <- Regex.run(~r/src="([^"]*search_data-[^"]+\.js)"/, html),
         file_url <- build_full_url(index_url, search_file),
         {:ok, %{status: 200, body: js_body}} <- Req.get(file_url) do
      parse_search_data_js(js_body)
    else
      _ ->
        {:error, :search_data_not_found}
    end
  end

  defp build_full_url(base, relative) do
    if String.starts_with?(relative, "http") do
      relative
    else
      URI.merge(base, relative) |> to_string()
    end
  end

  def parse_search_data_js(js_content) do
    json_str =
      cond do
        String.contains?(js_content, "searchData =") ->
          js_content
          |> String.split("searchData =", parts: 2)
          |> Enum.at(1)
          |> String.trim()
          |> String.trim_trailing(";")

        String.contains?(js_content, "searchNodes =") ->
          nodes =
            js_content
            |> String.split("searchNodes =", parts: 2)
            |> Enum.at(1)
            |> String.trim()
            |> String.trim_trailing(";")

          "{\"items\": #{nodes}}"

        true ->
          js_content
      end

    case Jason.decode(json_str) do
      {:ok, data} -> {:ok, data}
      {:error, err} -> {:error, {:invalid_json, err}}
    end
  end

  defp build_doc_item(package, version, item) when is_map(item) do
    ref = Map.get(item, "ref", "")
    title = Map.get(item, "title", Map.get(item, "name", ""))
    doc_text = Map.get(item, "doc", Map.get(item, "doc_html", ""))
    type = Map.get(item, "type", "doc")

    if doc_text != "" || title != "" do
      {module, function} = parse_title_and_module(title, ref)
      code_snippet = extract_code_snippet(doc_text)
      hexdocs_url = "https://hexdocs.pm/#{package}/#{version}/#{ref}"

      %{
        package: package,
        version: version,
        doc_type: to_string(type),
        module: module,
        function: function,
        signature: title,
        content: doc_text,
        code_snippet: code_snippet,
        hexdocs_url: hexdocs_url
      }
    else
      nil
    end
  end

  defp build_doc_item(_package, _version, _item), do: nil

  defp parse_title_and_module(title, ref) do
    cond do
      String.contains?(title, "/") ->
        case String.split(title, "/") do
          [mod, func] -> {mod, func}
          _ -> {parse_module_from_ref(ref), title}
        end

      String.contains?(ref, ".html#") ->
        case String.split(ref, ".html#") do
          [mod_file, func_id] ->
            mod = mod_file |> String.replace(".html", "")
            {mod, func_id}

          _ ->
            {parse_module_from_ref(ref), title}
        end

      true ->
        {parse_module_from_ref(ref), nil}
    end
  end

  defp parse_module_from_ref(ref) do
    ref
    |> String.split("#")
    |> List.first()
    |> String.replace(".html", "")
  end

  def extract_code_snippet(content) when is_binary(content) do
    case Regex.scan(~r/```(?:elixir)?\n(.*?)```/s, content) do
      [[_, snippet] | _] -> String.trim(snippet)
      _ -> nil
    end
  end

  def extract_code_snippet(_), do: nil

  defp attach_embedding(doc) do
    embedding_input = "#{doc.signature}\n#{doc.content}"

    case Mistral.embed(embedding_input) do
      {:ok, vector} when is_list(vector) ->
        Map.put(doc, :embedding, Pgvector.new(vector))

      _ ->
        Map.put(doc, :embedding, nil)
    end
  end
end
