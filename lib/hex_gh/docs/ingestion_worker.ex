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
        |> Enum.flat_map(&build_doc_items(package, resolved_version, &1))
        |> Enum.reject(&is_nil/1)

      docs_with_embeddings = attach_embeddings_batch(docs)
      save_docs(docs_with_embeddings, package, resolved_version)
    end
  end

  defp attach_embeddings_batch(docs) do
    docs
    |> Enum.chunk_every(50)
    |> Enum.flat_map(fn batch ->
      texts =
        Enum.map(batch, fn d ->
          sig = d.signature || ""
          content = d.content || ""
          text = String.trim("#{sig}\n#{content}")
          text = if text == "", do: d.title || "doc", else: text
          String.slice(text, 0, 4000)
        end)

      case Mistral.embed_batch(texts) do
        {:ok, vectors} when is_list(vectors) and length(vectors) == length(batch) ->
          Enum.zip_with(batch, vectors, fn doc, vec ->
            Map.put(doc, :embedding, Pgvector.new(vec))
          end)

        err ->
          Logger.error("[IngestionWorker] Mistral.embed_batch error: #{inspect(err)}")
          Enum.map(batch, &Map.put(&1, :embedding, nil))
      end
    end)
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
        fallback_resolve_package(package)

      error ->
        Logger.error("Failed to resolve version for package #{package}: #{inspect(error)}")
        {:error, :version_resolution_failed}
    end
  end

  defp resolve_version(_package, version), do: {:ok, version}

  defp fallback_resolve_package(package) do
    search_url = "https://hex.pm/api/packages?search=#{URI.encode(package)}"

    case Req.get(search_url, headers: [{"user-agent", "hex_gh/1.0"}]) do
      {:ok,
       %{
         status: 200,
         body: [%{"name" => _canonical_name, "releases" => [%{"version" => ver} | _]} | _]
       }} ->
        {:ok, ver}

      _ ->
        {:error, :package_not_found}
    end
  end

  defp fetch_search_data(package, version) do
    pkg_dashed = String.replace(package, "_", "-")

    primary_urls = [
      "https://#{pkg_dashed}.hexdocs.pm/#{version}/search_data.js",
      "https://#{pkg_dashed}.hexdocs.pm/search_data.js",
      "https://#{package}.hexdocs.pm/#{version}/search_data.js",
      "https://#{package}.hexdocs.pm/search_data.js",
      "https://hexdocs.pm/#{package}/#{version}/search_data.js"
    ]

    case Enum.find_value(primary_urls, &try_fetch_js/1) do
      {:ok, data} ->
        {:ok, data}

      _ ->
        fetch_search_data_fallback(package, version)
    end
  end

  defp try_fetch_js(url) do
    case Req.get(url, headers: [{"user-agent", "hex_gh/1.0"}], redirect: :follow) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case parse_search_data_js(body) do
          {:ok, data} -> {:ok, data}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp fetch_search_data_fallback(package, version) do
    pkg_dashed = String.replace(package, "_", "-")

    urls = [
      "https://#{pkg_dashed}.hexdocs.pm/#{version}/",
      "https://#{pkg_dashed}.hexdocs.pm/api-reference.html",
      "https://#{package}.hexdocs.pm/#{version}/",
      "https://#{package}.hexdocs.pm/api-reference.html",
      "https://hexdocs.pm/#{package}/#{version}/"
    ]

    Enum.find_value(urls, {:error, :search_data_not_found}, fn index_url ->
      with {:ok, %{status: 200, body: html}} when is_binary(html) <-
             Req.get(index_url, headers: [{"user-agent", "hex_gh/1.0"}], redirect: :follow),
           [_, search_file] <-
             Regex.run(~r/src="([^"]*(?:search_data|sidebar_items)-[^"]+\.js)"/, html),
           file_url <- build_full_url(index_url, search_file),
           {:ok, %{status: 200, body: js_body}} <- Req.get(file_url, redirect: :follow),
           {:ok, data} <- parse_search_data_js(js_body) do
        {:ok, data}
      else
        _ -> nil
      end
    end)
  end

  defp build_full_url(base, relative) do
    if String.starts_with?(relative, "http") do
      relative
    else
      URI.merge(base, relative) |> to_string()
    end
  end

  def parse_search_data_js(js_content) do
    cond do
      String.contains?(js_content, "sidebarNodes=") ->
        parse_sidebar_nodes_js(js_content)

      String.contains?(js_content, "searchData =") ->
        json_str =
          js_content
          |> String.split("searchData =", parts: 2)
          |> Enum.at(1)
          |> String.trim()
          |> String.trim_trailing(";")

        decode_json_items(json_str)

      String.contains?(js_content, "searchNodes =") ->
        nodes =
          js_content
          |> String.split("searchNodes =", parts: 2)
          |> Enum.at(1)
          |> String.trim()
          |> String.trim_trailing(";")

        decode_json_items("{\"items\": #{nodes}}")

      true ->
        decode_json_items(js_content)
    end
  end

  defp decode_json_items(json_str) do
    case Jason.decode(json_str) do
      {:ok, data} -> {:ok, data}
      {:error, err} -> {:error, {:invalid_json, err}}
    end
  end

  defp parse_sidebar_nodes_js(js_content) do
    json_str =
      js_content
      |> String.split("sidebarNodes=", parts: 2)
      |> Enum.at(1)
      |> String.trim()
      |> String.replace(~r/;*\s*$/, "")

    case Jason.decode(json_str) do
      {:ok, map} ->
        items = extract_items_from_sidebar_nodes(map)
        {:ok, %{"items" => items}}

      {:error, err} ->
        Logger.error("[IngestionWorker] sidebarNodes JSON decode error: #{inspect(err)}")
        {:error, {:invalid_json, err}}
    end
  end

  defp extract_items_from_sidebar_nodes(map) when is_map(map) do
    modules = Map.get(map, "modules", [])
    extras = Map.get(map, "extras", [])

    module_items =
      Enum.flat_map(modules, fn mod ->
        mod_id = Map.get(mod, "id", "")
        mod_title = Map.get(mod, "title", mod_id)

        mod_item = %{
          "ref" => "#{mod_id}.html",
          "title" => mod_title,
          "doc" => mod_title,
          "type" => "module"
        }

        node_groups = Map.get(mod, "nodeGroups", [])

        func_items =
          Enum.flat_map(node_groups, fn group ->
            key = Map.get(group, "key", "function")
            nodes = Map.get(group, "nodes", [])

            Enum.map(nodes, fn node ->
              node_id = Map.get(node, "id", "")
              anchor = Map.get(node, "anchor", node_id)

              %{
                "ref" => "#{mod_id}.html##{anchor}",
                "title" => "#{mod_title}.#{node_id}",
                "doc" => "#{mod_title}.#{node_id}",
                "type" => key
              }
            end)
          end)

        [mod_item | func_items]
      end)

    extra_items =
      Enum.map(extras, fn extra ->
        id = Map.get(extra, "id", "")
        title = Map.get(extra, "title", id)

        %{
          "ref" => "#{id}.html",
          "title" => title,
          "doc" => title,
          "type" => "guide"
        }
      end)

    module_items ++ extra_items
  end

  def build_doc_item(package, version, item) do
    case build_doc_items(package, version, item) do
      [first | _] -> first
      _ -> nil
    end
  end

  def build_doc_items(package, version, item) when is_map(item) do
    ref = Map.get(item, "ref", "")
    title = Map.get(item, "title", Map.get(item, "name", ""))
    doc_text = Map.get(item, "doc", Map.get(item, "doc_html", ""))
    type = to_string(Map.get(item, "type", "doc"))
    hexdocs_url = "https://hexdocs.pm/#{package}/#{version}/#{ref}"

    content =
      if type == "guide" and (doc_text == "" or String.length(doc_text) < 100) do
        fetched = fetch_guide_content(hexdocs_url)
        if fetched != "", do: fetched, else: doc_text
      else
        doc_text
      end

    if content != "" || title != "" do
      {module, function} = parse_title_and_module(title, ref)

      if type == "guide" or String.length(content) > 1500 do
        chunk_content(content, %{
          package: package,
          version: version,
          doc_type: type,
          module: module,
          function: function,
          base_signature: title,
          base_url: hexdocs_url
        })
      else
        code_snippet = extract_code_snippet(content)

        [
          %{
            package: package,
            version: version,
            doc_type: type,
            module: module,
            function: function,
            signature: title,
            content: content,
            code_snippet: code_snippet,
            hexdocs_url: hexdocs_url
          }
        ]
      end
    else
      []
    end
  end

  def build_doc_items(_package, _version, _item), do: []

  @doc """
  Fetches HTML content for a guide page from HexDocs and extracts plain text / markdown content.
  """
  def fetch_guide_content(url) when is_binary(url) do
    case Req.get(url, headers: [{"user-agent", "hex_gh/1.0"}], redirect: :follow) do
      {:ok, %{status: 200, body: html}} when is_binary(html) ->
        extract_text_from_html(html)

      _ ->
        ""
    end
  end

  def fetch_guide_content(_), do: ""

  @doc """
  Strips HTML tags and converts HTML guide pages to plain text.
  """
  def extract_text_from_html(html) when is_binary(html) do
    content_html =
      case Regex.run(
             ~r/<(?:div|main)[^>]*id=["'](?:content|main)["'][^>]*>(.*)<\/(?:div|main)>/s,
             html
           ) do
        [_, inner] -> inner
        _ -> html
      end

    content_html
    |> String.replace(~r/<script.*?>.*?<\/script>/is, "")
    |> String.replace(~r/<style.*?>.*?<\/style>/is, "")
    |> String.replace(~r/<(p|h[1-6]|li|br|div|tr|section|article)[^>]*>/i, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> decode_html_entities()
    |> String.replace(~r/\n\s*\n/, "\n\n")
    |> String.trim()
  end

  def extract_text_from_html(_), do: ""

  defp decode_html_entities(text) when is_binary(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
  end

  defp chunk_content(content, %{
         package: package,
         version: version,
         doc_type: type,
         module: module,
         function: function,
         base_signature: title,
         base_url: base_url
       }) do
    chunks =
      case TextChunker.split(content, chunk_size: 400, chunk_overlap: 40) do
        {:ok, list} -> list
        list when is_list(list) -> list
        _ -> [content]
      end

    total_chunks = length(chunks)

    chunks
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, idx} ->
      chunk_text =
        case chunk do
          %TextChunker.Chunk{text: t} -> t
          t when is_binary(t) -> t
          _ -> to_string(chunk)
        end

      {sig_suffix, url_anchor} =
        if total_chunks > 1 do
          {" - Part #{idx}", "#part-#{idx}"}
        else
          {"", ""}
        end

      signature = "#{title}#{sig_suffix}"
      hexdocs_url = "#{base_url}#{url_anchor}"
      code_snippet = extract_code_snippet(chunk_text)

      %{
        package: package,
        version: version,
        doc_type: type,
        module: module,
        function: function,
        signature: signature,
        content: chunk_text,
        code_snippet: code_snippet,
        hexdocs_url: hexdocs_url
      }
    end)
  end

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
end
