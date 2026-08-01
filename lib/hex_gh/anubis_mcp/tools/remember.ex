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
        "Technical learning, pain point, pattern, or architectural decision to save to project memory. " <>
          "Synthesize the text to include: 1) What occurred / symptom, 2) Root cause, 3) Solution / fix, " <>
          "4) Technologies/stack involved, and 5) Package name, version constraints (e.g. 'pgvector ~> 0.3'), " <>
          "and GitHub repo if applicable. " <>
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

  defp log_decision(%{action: "discard"}, neighbors) do
    top_sim = neighbors |> Enum.map(fn n -> 1.0 - n.distance end) |> Enum.max(fn -> 0.0 end)
    Logger.info("[KB decision] discard (too similar, top_sim=#{Float.round(top_sim, 3)})")
    emit_decision_telemetry("discard", "n/a", true, top_sim)
    :ok
  end

  defp log_decision(%{action: "create"}, []) do
    Logger.info("[KB decision] create (no neighbors)")
    emit_decision_telemetry("create", "n/a", false, 0.0)
    :ok
  end

  defp log_decision(%{action: "create"}, neighbors) do
    top_sim = neighbors |> Enum.map(fn n -> 1.0 - n.distance end) |> Enum.max(fn -> 0.0 end)
    top = Enum.map(neighbors, fn n -> {n.title, Float.round(1.0 - n.distance, 3)} end)
    Logger.info("[KB decision] create despite #{length(neighbors)} neighbor(s): #{inspect(top)}")
    emit_decision_telemetry("create", "n/a", true, top_sim)
    :ok
  end

  defp log_decision(%{action: action, id: id} = decision, neighbors) do
    strategy = Map.get(decision, :strategy, "n/a")
    top_sim = neighbors |> Enum.map(fn n -> 1.0 - n.distance end) |> Enum.max(fn -> 0.0 end)
    Logger.info("[KB decision] #{action} (#{strategy}) on entry ##{id}")
    emit_decision_telemetry(action, strategy, true, top_sim)
    :ok
  end

  defp log_decision(decision, _neighbors) do
    Logger.info("[KB decision] #{inspect(decision)}")
    :ok
  end

  defp emit_decision_telemetry(action, strategy, had_neighbors, top_similarity) do
    :telemetry.execute(
      [:hex_gh, :knowledge, :decision],
      %{count: 1, top_similarity: Float.round(top_similarity, 4)},
      %{action: action, strategy: strategy, had_neighbors: to_string(had_neighbors)}
    )
  end

  @doc false
  def process(text) do
    with {:ok, embedding} <- Mistral.embed(text),
         neighbors <- KnowledgeBase.search(embedding, limit: 3),
         {:ok, decision} <- decide(text, neighbors),
         :ok <- log_decision(decision, neighbors),
         {:ok, result} <- apply_decision(decision) do
      Logger.info("Knowledge base: #{result}")
    else
      {:error, reason} ->
        Logger.error("Knowledge base remember failed: #{inspect(reason)}")
    end
  end

  defp apply_decision(%{action: "discard"}) do
    {:ok, "discarded (too similar to existing entry)"}
  end

  defp apply_decision(decision) do
    with {:ok, structured} <- structure_text(decision.content),
         embedding_text <- build_embedding_text(structured, decision.content),
         {:ok, final_embedding} <- Mistral.embed(embedding_text) do
      result = execute_decision(decision, structured, final_embedding)
      {:ok, "#{result.action} — #{result.title}"}
    end
  end

  defp build_embedding_text(structured, content) do
    meta = stringify_keys(structured.metadata)

    stack_list = Map.get(meta, "stack", [])

    stack_str =
      if is_list(stack_list) and stack_list != [], do: Enum.join(stack_list, ", "), else: "N/A"

    symptom = Map.get(meta, "symptom", "N/A")
    fix = Map.get(meta, "fix", "N/A")
    domain = Map.get(meta, "domain", "general")
    package = Map.get(meta, "package", "N/A")
    version = Map.get(meta, "package_version", "N/A")

    """
    [#{structured.kind} | #{domain}] #{structured.title}
    Stack: #{stack_str}
    Package: #{package} (#{version})
    Symptom: #{symptom}
    Fix: #{fix}
    Summary: #{content}
    """
    |> String.trim()
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
    - **Preserving prior learnings**: Do NOT use "replace" unless the old information is factually wrong, obsolete, or superseded. If the new learning adds a complementary aspect or new facet to an existing topic (e.g. embedding model choice vs chat model choice), you MUST use "merge" or "append" to preserve all learnings in the synthesized content.
    - **Package versions**: A fix for library v1 may not apply to v2. If versions differ, prefer "create" to keep both.
    - **API changes**: If an API or behavior changed between versions, the old entry is still valid for its version — prefer "append" or "create".
    - **Evolving fixes**: If the fix improved (e.g. workaround → proper solution), use "replace" with the better fix.

    Return ONLY valid JSON with one of:
    1. {"action": "create", "content": "<the new learning text>"} — genuinely new topic, or version-specific knowledge that shouldn't overwrite the old
    2. {"action": "discard"} — the new learning is essentially the same as an existing entry with no additional value. Use this when similarity is very high and no new information is present.
    3. {"action": "update", "id": <existing_id>, "strategy": "append", "content": "<old content + new details>"} — the new learning extends the old with additional context, edge cases, or version notes. PRESERVES all existing content.
    4. {"action": "update", "id": <existing_id>, "strategy": "merge", "content": "<synthesized content combining old + new>"} — both contain partial truths that should be combined into one comprehensive entry
    5. {"action": "update", "id": <existing_id>, "strategy": "replace", "content": "<new content>"} — ONLY if the old info is factually wrong/superseded by the new learning
    6. {"action": "deprecate", "id": <existing_id>, "reason": "<why entry is obsolete/deprecated>"} — the existing entry is completely wrong, dangerous, or obsolete and should be soft-deleted

    DECISION GUIDE (in order of preference):
    - Similarity > 0.9 and no new facts → "discard"
    - Similarity > 0.8 and new details/edge cases → "append"
    - Overlapping but complementary info → "merge"
    - Old info is wrong or superseded → "replace"
    - Completely different topic despite embedding proximity → "create"

    The final content must be self-contained and comprehensive. Include version/date qualifiers when relevant (e.g. "As of pgvector 0.3..." or "Fixed in Phoenix 1.8+").
    """

    case Mistral.chat([%{role: "user", content: prompt}], [], model: Mistral.large_model()) do
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

  defp execute_decision(%{action: "deprecate", id: id} = decision, _structured, _embedding) do
    dec_meta = stringify_keys(decision)
    reason = Map.get(dec_meta, "reason")
    Logger.info("Knowledge base: deprecating entry ##{id} (reason: #{inspect(reason)})")

    case KnowledgeBase.deprecate(id, reason) do
      {:ok, entry} ->
        %{action: "deprecated", id: entry.id, title: entry.title}

      {:error, _} ->
        %{action: "error (deprecate failed)", id: id}
    end
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
    - "stack": list of technologies involved, lowercase (e.g. ["elixir", "postgres", "postgrex", "docker", "caddy"]).
      IMPORTANT: Infer implicit stack layers even if not explicitly named in text:
      - Mentions of Caddyfile / reverse_proxy / 502 / 504 -> include "caddy", "deploy"
      - Mentions of mix.exs / Plug / GenServer / LiveView / Ecto -> include "elixir", "phoenix"
      - Mentions of docker / docker-compose / container -> include "docker"
      - Mentions of pgvector / postgrex / psql -> include "postgres"
    - "symptom": what was observed or error message (optional, null if N/A)
    - "cause": root cause (optional, null if N/A)
    - "fix": how it was resolved (optional, null if N/A)
    - "package": hex.pm package name if applicable (e.g. "phoenix", "pgvector", "anubis_mcp"), null otherwise
    - "package_version": version or version constraint this applies to (e.g. "~> 0.3", "3.0.0-beta.4"), null if N/A
    - "resolved_in": version where the issue was fixed, if known (e.g. "1.8.0"), null otherwise
    - "repo": GitHub repo (e.g. "phoenixframework/phoenix", "dwyl/hexpm-github-search") if applicable, null otherwise

    Text: #{text}
    """

    case Mistral.chat([%{role: "user", content: prompt}], [], model: Mistral.small_model()) do
      {:ok, %{"content" => content}} ->
        case Jason.decode(clean_json(content)) do
          {:ok, parsed} ->
            metadata = extract_metadata(parsed)
            {kind, metadata} = normalize_kind(parsed["kind"], metadata)

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
      {:ok, %{"action" => "discard"}} ->
        {:ok, %{action: "discard"}}

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

  defp extract_metadata(parsed) do
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
  end

  @allowed_kinds ~w(learning pain_point decision pattern package_note)

  defp normalize_kind(nil, metadata), do: {"learning", metadata}
  defp normalize_kind(kind, metadata) when kind in @allowed_kinds, do: {kind, metadata}

  defp normalize_kind(raw_kind, metadata) do
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

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
