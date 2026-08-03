defmodule HexGh.MCP.Tools.Remember do
  @moduledoc "Save a technical learning or pain point to the knowledge base."

  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response
  alias HexGh.AI.Mistral
  alias HexGh.Knowledge.Schemas
  alias HexGh.Knowledge.Vocabulary
  alias HexGh.KnowledgeBase

  require Logger

  # Below this, neighbours are not close enough to be worth a curator call.
  @similarity_threshold 0.7
  # Above this, a submission adding no new facts is a duplicate.
  @duplicate_threshold 0.9

  # How many neighbours to retrieve as curation candidates. The decision target
  # has consistently been the nearest one; the second is carried only so the
  # curator can see when a submission spans two entries and should be merged.
  # Anything beyond that has never changed an outcome and is pure prompt cost.
  @neighbor_limit 2

  # Only the nearest neighbour is rendered in full. The discard rule turns on
  # whether the submission "contains no fact absent from the neighbour", which
  # cannot be judged from an excerpt — so the likely target keeps its complete
  # text, while the runner-up is summarised.
  @excerpt_chars 400

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
    request_id = generate_request_id()

    reply =
      case KnowledgeBase.open_decision(request_id, text) do
        {:ok, _} ->
          Task.Supervisor.start_child(HexGh.TaskSupervisor, fn ->
            process(text, request_id)
          end)

          %{
            accepted: true,
            status: "processing",
            request_id: request_id,
            note:
              "Curation runs asynchronously and may discard, append, merge, replace or deprecate. " <>
                "Look up this request_id to see what was actually done."
          }

        {:error, reason} ->
          Logger.error("Knowledge base could not open decision record: #{inspect(reason)}")
          %{accepted: false, status: "failed", detail: "could not record request"}
      end

    {:reply, Response.tool() |> Response.text(Jason.encode!(reply)), frame}
  end

  defp generate_request_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
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
  def process(text, request_id \\ nil) do
    with {:ok, embedding} <- Mistral.embed(text),
         neighbors <- KnowledgeBase.search(embedding, limit: @neighbor_limit),
         {:ok, decision} <- decide(text, neighbors),
         :ok <- log_decision(decision, neighbors),
         {:ok, result} <- apply_decision(decision) do
      Logger.info("Knowledge base: #{result.detail}")
      record_outcome(request_id, "applied", decision, neighbors, result)
    else
      {:error, reason} ->
        Logger.error("Knowledge base remember failed: #{inspect(reason)}")
        record_failure(request_id, reason)
    end
  end

  defp record_outcome(nil, _status, _decision, _neighbors, _result), do: :ok

  defp record_outcome(request_id, status, decision, neighbors, result) do
    KnowledgeBase.close_decision(request_id, %{
      status: status,
      action: result.action,
      strategy: Map.get(decision, :strategy),
      target_id: Map.get(result, :id),
      top_similarity: top_similarity(neighbors),
      curated: Map.get(decision, :curated, false),
      detail: result.detail
    })

    :ok
  end

  defp record_failure(nil, _reason), do: :ok

  defp record_failure(request_id, reason) do
    KnowledgeBase.close_decision(request_id, %{
      status: "failed",
      detail: "remember failed: #{inspect(reason)}"
    })

    :ok
  end

  defp top_similarity([]), do: 0.0

  defp top_similarity(neighbors) do
    neighbors |> Enum.map(fn n -> 1.0 - n.distance end) |> Enum.max(fn -> 0.0 end)
  end

  # A discard is a deliberate no-op, but it is still an outcome the caller has
  # to be able to distinguish from a save.
  defp apply_decision(%{action: "discard"}) do
    {:ok, %{action: "discarded", detail: "discarded (too similar to an existing entry)"}}
  end

  # Deprecation only flips a flag on an existing row, so it needs neither
  # structuring nor a fresh embedding.
  defp apply_decision(%{action: "deprecate", id: id} = decision) do
    reason = Map.get(decision, :reason)
    Logger.info("Knowledge base: deprecating entry ##{id} (reason: #{inspect(reason)})")

    case KnowledgeBase.deprecate(id, reason) do
      {:ok, entry} ->
        {:ok,
         %{
           action: "deprecated",
           id: entry.id,
           title: entry.title,
           detail: "deprecated ##{entry.id} — #{entry.title}"
         }}

      {:error, reason} ->
        {:error, {:deprecate_failed, id, reason}}
    end
  end

  defp apply_decision(decision) do
    with {:ok, structured} <- fetch_or_structure_text(decision),
         embedding_text <- build_embedding_text(structured, decision.content),
         {:ok, final_embedding} <- Mistral.embed(embedding_text) do
      result = execute_decision(decision, structured, final_embedding)
      title = Map.get(result, :title, "n/a")
      {:ok, Map.put(result, :detail, "#{result.action} — #{title}")}
    end
  end

  defp fetch_or_structure_text(%{structured: structured}) when is_map(structured),
    do: {:ok, structured}

  defp fetch_or_structure_text(decision), do: structure_text(decision.content)

  defp build_embedding_text(structured, content) do
    meta = stringify_keys(structured.metadata)

    stack_list = Map.get(meta, "stack", [])

    stack_str =
      if is_list(stack_list) and stack_list != [], do: Enum.join(stack_list, ", "), else: "N/A"

    symptom = Map.get(meta, "symptom", "N/A")
    fix = Map.get(meta, "fix", "N/A")
    package = Map.get(meta, "package", "N/A")
    version = Map.get(meta, "package_version", "N/A")

    """
    [#{structured.kind}] #{structured.title}
    Stack: #{stack_str}
    Package: #{package} (#{version})
    Symptom: #{symptom}
    Fix: #{fix}
    Summary: #{content}
    """
    |> String.trim()
  end

  # `curated: false` marks a create that never reached the LLM because nothing
  # cleared the floor. Recording it separately is what makes the floor itself
  # measurable rather than a guess.
  defp decide(text, []) do
    {:ok, %{action: "create", content: text, curated: false}}
  end

  defp decide(text, neighbors) do
    close = Enum.filter(neighbors, fn n -> 1.0 - n.distance >= @similarity_threshold end)

    if close == [] do
      {:ok, %{action: "create", content: text, curated: false}}
    else
      with {:ok, decision} <- ask_mistral(text, close) do
        {:ok, Map.put(decision, :curated, true)}
      end
    end
  end

  defp ask_mistral(text, neighbors) do
    existing =
      neighbors
      |> Enum.sort_by(& &1.distance)
      |> Enum.with_index()
      |> Enum.map_join("\n\n", fn {n, i} -> render_neighbor(n, i) end)

    prompt = """
    You are a knowledge base curator. A new learning is being saved. Similar entries already exist.
    Today's date: #{Date.utc_today()}.

    NEW LEARNING:
    #{text}

    EXISTING ENTRIES (each shows its measured similarity to the new learning):
    #{existing}

    Work through the two steps in order. STEP 1 takes precedence over STEP 2.

    STEP 1 — Does the new learning CONTRADICT or SUPERSEDE any existing entry?
    A correction is by construction almost identical to the thing it corrects, so it
    will show a very high similarity. High similarity is therefore NOT evidence that a
    correction is a duplicate. If the new learning states that something in an existing
    entry is now wrong, renamed, moved, removed or otherwise out of date:
      - the old entry is wrong but the topic still exists  -> "replace"
      - the old entry is wholly obsolete                   -> "deprecate"
    Never answer "discard" for a correction, no matter how high the similarity.

    STEP 2 — Otherwise, apply the similarity bands:
      - similarity > #{@duplicate_threshold} AND the new learning contains no fact absent from the neighbour -> "discard"
      - similarity between #{@similarity_threshold} and #{@duplicate_threshold}, new learning adds detail, edge cases or version notes -> "append"
      - similarity between #{@similarity_threshold} and #{@duplicate_threshold}, both hold partial truths that belong together -> "merge"
      - the topic is genuinely different despite embedding proximity -> "create"

    Additional rules:
    - **Package versions**: a fix for library v1 may not apply to v2. If versions differ, prefer "create" to keep both.
    - **API changes**: if behaviour changed between versions, the old entry is still valid for its version — prefer "append" or "create".
    - **Preserve prior learnings**: outside of STEP 1, never drop information. "append" and "merge" must carry over the existing content.
    - **Preserve structure**: if either the new learning or the neighbour states a symptom, a root cause or a fix, the content you return must still state them. Merging must not silently drop these.
    - **One topic per entry**: if the new learning is about a different subject than the neighbour, choose "create" rather than attaching it to an unrelated entry.

    The response shape is fixed by the schema attached to this request; every field
    carries its own description there. Reason through the workflow above before
    committing to an action. Include version/date qualifiers in the content where
    relevant (e.g. "As of pgvector 0.3..." or "Fixed in Phoenix 1.8+").
    """

    case Mistral.chat([%{role: "user", content: prompt}], [],
           model: Mistral.large_model(),
           json_schema: Schemas.curation(),
           schema_name: "curation_decision"
         ) do
      {:ok, %{"content" => content}} ->
        parse_decision(content, text)

      {:error, _} = error ->
        error
    end
  end

  # Nearest neighbour: full text, because the discard rule turns on whether the
  # submission contains a fact absent from it, which an excerpt cannot answer.
  # The label stays neutral: calling it the "likely target" biased the curator
  # towards attaching to it instead of creating a separate entry.
  defp render_neighbor(n, 0) do
    """
    [ID: #{n.id}] #{n.title}
    Similarity to the new learning: #{format_similarity(n)}  (full content)
    Kind: #{n.kind}
    Content: #{n.content}
    Metadata: #{Jason.encode!(n.metadata)}
    Last updated: #{Map.get(n, :updated_at, "unknown")}
    """
  end

  # Runner-up: excerpt only. It is present so the curator can recognise a
  # submission that spans two entries and belongs merged, which needs the gist
  # rather than the full body.
  defp render_neighbor(n, _rank) do
    """
    [ID: #{n.id}] #{n.title}
    Similarity to the new learning: #{format_similarity(n)}  (excerpt only)
    Kind: #{n.kind}
    Content (first #{@excerpt_chars} chars): #{excerpt(n.content)}
    Metadata: #{Jason.encode!(n.metadata)}
    """
  end

  defp excerpt(content) when is_binary(content) do
    if String.length(content) > @excerpt_chars do
      String.slice(content, 0, @excerpt_chars) <> " […truncated]"
    else
      content
    end
  end

  defp excerpt(content), do: content

  defp format_similarity(%{distance: distance}) when is_float(distance) do
    "#{Float.round((1.0 - distance) * 100, 1)}%"
  end

  defp format_similarity(_), do: "unknown"

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
    Extract the structured fields describing this technical learning. The response
    shape is fixed by the schema attached to this request and every field carries
    its own description there.

    Text: #{text}
    """

    case Mistral.chat([%{role: "user", content: prompt}], [],
           model: Mistral.small_model(),
           json_schema: Schemas.structuring(),
           schema_name: "structured_learning"
         ) do
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
               kind: Vocabulary.infer_kind(%{}),
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

        resolve_update(
          parse_id(id),
          merged,
          strategy,
          build_structured_from_parsed(merged, parsed)
        )

      # Previously missing: the curator prompt offers "deprecate" as option 6,
      # but with no clause for it the response fell through to the catch-all and
      # was turned into a "create". Soft-deprecation could never actually fire,
      # which is why superseded entries stayed live alongside their replacements.
      {:ok, %{"action" => "deprecate", "id" => id} = parsed} ->
        resolve_deprecate(parse_id(id), parsed["reason"], original_text)

      {:ok, %{"action" => "create", "content" => new_content} = parsed} ->
        {:ok,
         %{
           action: "create",
           content: new_content,
           structured: build_structured_from_parsed(new_content, parsed)
         }}

      _ ->
        {:ok, %{action: "create", content: original_text}}
    end
  end

  defp resolve_update({:ok, parsed_id}, merged, strategy, structured) do
    {:ok,
     %{
       action: "update",
       id: parsed_id,
       content: merged,
       strategy: strategy,
       structured: structured
     }}
  end

  defp resolve_update(:error, merged, _strategy, structured) do
    {:ok, %{action: "create", content: merged, structured: structured}}
  end

  # The curator already returns the structured fields alongside its decision, so
  # the separate small-model structuring call is redundant on that path. It now
  # runs only when the curator never did — the short-circuit below the floor.
  defp build_structured_from_parsed(text, parsed) when is_map(parsed) do
    metadata = extract_metadata(parsed)
    {kind, metadata} = normalize_kind(parsed["kind"], metadata)

    %{
      kind: kind,
      title: parsed["title"] || String.slice(text, 0, 80),
      content: text,
      metadata: metadata
    }
  end

  defp resolve_deprecate({:ok, parsed_id}, reason, original_text) do
    {:ok, %{action: "deprecate", id: parsed_id, reason: reason, content: original_text}}
  end

  defp resolve_deprecate(:error, _reason, original_text) do
    {:ok, %{action: "create", content: original_text}}
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
      stack: Vocabulary.normalize_tags(parsed["stack"] || []),
      package: parsed["package"],
      package_version: parsed["package_version"],
      resolved_in: parsed["resolved_in"],
      repo: parsed["repo"]
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_kind(kind, metadata) when is_binary(kind) do
    if kind in Vocabulary.kinds() do
      {kind, metadata}
    else
      # Inferred from the fields present rather than defaulting to a constant.
      # A fixed fallback is how the previous `learning` value came to hold every
      # row in the table, which left the `kind` filter unable to discriminate.
      {Vocabulary.infer_kind(metadata), Map.put(metadata, :raw_kind, kind)}
    end
  end

  defp normalize_kind(nil, metadata), do: {Vocabulary.infer_kind(metadata), metadata}

  defp normalize_kind(raw_kind, metadata) do
    {Vocabulary.infer_kind(metadata), Map.put(metadata, :raw_kind, inspect(raw_kind))}
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
