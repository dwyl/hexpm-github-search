defmodule HexGh.MCP.Tools.Remember do
  @moduledoc "Save a technical learning or pain point to the knowledge base."

  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response
  alias HexGh.AI.Mistral
  alias HexGh.KnowledgeBase

  require Logger

  @similarity_threshold 0.7

  schema do
    field(:text, {:required, :string},
      description:
        "Raw learning text to structure and save (e.g. a pain point, pattern, or decision). " <>
          "Include version details when relevant: package name, version (e.g. 'pgvector ~> 0.3'), " <>
          "repo (e.g. 'phoenixframework/phoenix'), and whether a fix was introduced in a specific version. " <>
          "Example: 'In anubis_mcp (jfim/anubis-mcp, branch non-upstreamed-fixes), the SSE keepalive " <>
          "defaults to 5s which causes timeouts behind Caddy. Fixed by adding flush_interval -1 to Caddyfile.'"
    )
  end

  @impl true
  def execute(%{text: text}, frame) do
    Task.Supervisor.start_child(HexGh.TaskSupervisor, fn ->
      process(text)
    end)

    {:reply,
     Response.tool() |> Response.text(Jason.encode!(%{accepted: true, status: "processing"})),
     frame}
  end

  defp process(text) do
    with {:ok, embedding} <- Mistral.embed(text),
         neighbors <- KnowledgeBase.search(embedding, limit: 3),
         {:ok, decision} <- decide(text, neighbors),
         {:ok, structured} <- structure_text(decision.content),
         {:ok, final_embedding} <- Mistral.embed("#{structured.title}: #{structured.content}") do
      result = execute_decision(decision, structured, final_embedding)
      Logger.info("Knowledge base: #{result.action} — #{result.title}")
    else
      {:error, reason} ->
        Logger.error("Knowledge base remember failed: #{inspect(reason)}")
    end
  end

  defp decide(text, []) do
    {:ok, %{action: "create", content: text}}
  end

  defp decide(text, neighbors) do
    close = Enum.filter(neighbors, fn n -> 1.0 - n.distance >= @similarity_threshold end)

    if close == [] do
      {:ok, %{action: "create", content: text}}
    else
      ask_mistral(text, close)
    end
  end

  defp ask_mistral(text, neighbors) do
    existing =
      Enum.map_join(neighbors, "\n\n", fn n ->
        """
        [ID: #{n.id}] #{n.title}
        Kind: #{n.kind}
        Content: #{n.content}
        Metadata: #{Jason.encode!(n.metadata)}
        Last updated: #{Map.get(n, :updated_at, "unknown")}
        """
      end)

    prompt = """
    You are a knowledge base curator. A new learning is being saved. Similar entries already exist.
    Today's date: #{Date.utc_today()}.

    NEW LEARNING:
    #{text}

    EXISTING ENTRIES:
    #{existing}

    Decide what to do. Pay special attention to:
    - **Package versions**: A fix for library v1 may not apply to v2. If versions differ, prefer "create" to keep both.
    - **API changes**: If an API or behavior changed between versions, the old entry is still valid for its version — prefer "append" or "create".
    - **Timestamps**: Older entries may be outdated. If the new learning explicitly corrects old info, use "replace".
    - **Evolving fixes**: If the fix improved (e.g. workaround → proper solution), use "replace" with the better fix.

    Return ONLY valid JSON with one of:
    1. {"action": "create", "content": "<the new learning text>"} — genuinely new, or version-specific knowledge that shouldn't overwrite the old
    2. {"action": "update", "id": <existing_id>, "strategy": "replace", "content": "<new content>"} — the new learning supersedes/corrects the old (e.g. fix changed, info is outdated)
    3. {"action": "update", "id": <existing_id>, "strategy": "append", "content": "<old content + new details>"} — the new learning extends the old with additional context, edge cases, or version notes
    4. {"action": "update", "id": <existing_id>, "strategy": "merge", "content": "<synthesized content>"} — both contain partial truths that should be combined into one comprehensive entry

    The final content must be self-contained and comprehensive. Include version/date qualifiers when relevant (e.g. "As of pgvector 0.3..." or "Fixed in Phoenix 1.8+").
    """

    case Mistral.chat([%{role: "user", content: prompt}], [], model: "mistral-large-latest") do
      {:ok, %{"content" => content}} ->
        parse_decision(content, text)

      {:error, _} = error ->
        error
    end
  end

  defp execute_decision(%{action: "create"}, structured, embedding) do
    {:ok, entry} = KnowledgeBase.save(Map.put(structured, :embedding, embedding))
    %{action: "created", id: entry.id, title: entry.title}
  end

  defp execute_decision(%{action: "update", id: id, strategy: strategy}, structured, embedding) do
    Logger.info("Knowledge base: #{strategy} on entry ##{id}")
    attrs = Map.put(structured, :embedding, embedding)

    case KnowledgeBase.update(id, attrs) do
      {:ok, entry} ->
        %{action: "updated", id: entry.id, title: entry.title}

      {:error, _} ->
        {:ok, entry} = KnowledgeBase.save(Map.put(structured, :embedding, embedding))
        %{action: "created (fallback)", id: entry.id, title: entry.title}
    end
  end

  defp structure_text(text) do
    prompt = """
    Extract structured fields from this technical learning. Return ONLY valid JSON with these fields:
    - "title": short summary (max 80 chars)
    - "kind": one of "learning", "pain_point", "decision", "pattern", "package_note"
    - "domain": one of "deploy" (infrastructure, Docker, reverse proxy, CI/CD, migrations), "config" (runtime.exs, env vars, app config), "code" (patterns, APIs, library usage), "debug" (error resolution, troubleshooting)
    - "stack": list of technologies involved, lowercase (e.g. ["elixir", "postgres", "postgrex", "docker"]). Include all relevant layers — e.g. Postgrex is both "elixir" and "postgres".
    - "symptom": what was observed (optional, null if N/A)
    - "cause": root cause (optional, null if N/A)
    - "fix": how it was resolved (optional, null if N/A)
    - "package": hex.pm package name if applicable (e.g. "phoenix", "pgvector"), null otherwise
    - "package_version": version or version constraint this applies to (e.g. "~> 0.3", "3.0.0-beta.4"), null if N/A
    - "resolved_in": version where the issue was fixed, if known (e.g. "1.8.0"), null otherwise
    - "repo": GitHub repo (e.g. "phoenixframework/phoenix") if applicable, null otherwise

    Text: #{text}
    """

    case Mistral.chat([%{role: "user", content: prompt}], [], model: "mistral-small-latest") do
      {:ok, %{"content" => content}} ->
        case Jason.decode(clean_json(content)) do
          {:ok, parsed} ->
            metadata =
              %{
                symptom: parsed["symptom"],
                cause: parsed["cause"],
                fix: parsed["fix"],
                domain: parsed["domain"],
                stack: parsed["stack"] || [],
                package: parsed["package"],
                package_version: parsed["package_version"],
                resolved_in: parsed["resolved_in"],
                repo: parsed["repo"]
              }
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()

            raw_kind = parsed["kind"]
            allowed_kinds = ~w(learning pain_point decision pattern package_note)

            {kind, metadata} =
              cond do
                is_nil(raw_kind) ->
                  {"learning", metadata}

                raw_kind in allowed_kinds ->
                  {raw_kind, metadata}

                true ->
                  normalized =
                    case raw_kind do
                      "bug" -> "pain_point"
                      "caveat" -> "pain_point"
                      "workaround" -> "pain_point"
                      "tip" -> "learning"
                      "info" -> "learning"
                      _ -> "learning"
                    end

                  {normalized, Map.put(metadata, :raw_kind, raw_kind)}
              end

            {:ok,
             %{
               kind: kind,
               title: parsed["title"] || String.slice(text, 0, 80),
               content: text,
               metadata: metadata
             }}

          {:error, _} ->
            {:ok,
             %{
               kind: "learning",
               title: String.slice(text, 0, 80),
               content: text,
               metadata: %{}
             }}
        end

      {:error, _} = error ->
        error
    end
  end

  defp clean_json(content) do
    content
    |> String.replace(~r/^```json\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()
  end

  defp parse_decision(content, original_text) do
    case Jason.decode(clean_json(content)) do
      {:ok, %{"action" => "update", "id" => id, "content" => merged} = parsed} ->
        strategy = parsed["strategy"] || "merge"
        resolve_update(parse_id(id), merged, strategy)

      {:ok, %{"action" => "create", "content" => new_content}} ->
        {:ok, %{action: "create", content: new_content}}

      _ ->
        {:ok, %{action: "create", content: original_text}}
    end
  end

  defp resolve_update({:ok, parsed_id}, merged, strategy) do
    {:ok, %{action: "update", id: parsed_id, content: merged, strategy: strategy}}
  end

  defp resolve_update(:error, merged, _strategy) do
    {:ok, %{action: "create", content: merged}}
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error
end
