defmodule HexGh.MCP.Tools.Remember do
  @moduledoc "Save a technical learning or pain point to the knowledge base."

  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response
  alias Anubis.MCP.Error
  alias HexGh.AI.Mistral
  alias HexGh.KnowledgeBase

  schema do
    field(:text, {:required, :string},
      description: "Raw learning text to structure and save (e.g. a pain point, pattern, or decision)"
    )
  end

  @impl true
  def execute(%{text: text}, frame) do
    with {:ok, structured} <- structure_text(text),
         {:ok, embedding} <- Mistral.embed(text),
         {:ok, entry} <- KnowledgeBase.save(Map.put(structured, :embedding, embedding)) do
      result =
        Jason.encode!(%{
          saved: true,
          id: entry.id,
          title: entry.title,
          kind: entry.kind
        })

      {:reply, Response.tool() |> Response.text(result), frame}
    else
      {:error, reason} ->
        {:error, Error.execution("Failed to save: #{inspect(reason)}"), frame}
    end
  end

  defp structure_text(text) do
    prompt = """
    Extract structured fields from this technical learning. Return ONLY valid JSON with these fields:
    - "title": short summary (max 80 chars)
    - "kind": one of "learning", "pain_point", "decision", "pattern", "package_note"
    - "symptom": what was observed (optional, null if N/A)
    - "cause": root cause (optional, null if N/A)
    - "fix": how it was resolved (optional, null if N/A)
    - "context": list of relevant tags (e.g. ["Docker", "PostgreSQL"])

    Text: #{text}
    """

    messages = [%{role: "user", content: prompt}]

    case Mistral.chat(messages, [], model: "mistral-small-latest") do
      {:ok, %{"content" => content}} ->
        case Jason.decode(clean_json(content)) do
          {:ok, parsed} ->
            {:ok,
             %{
               kind: parsed["kind"] || "learning",
               title: parsed["title"] || String.slice(text, 0, 80),
               content: text,
               metadata: %{
                 symptom: parsed["symptom"],
                 cause: parsed["cause"],
                 fix: parsed["fix"],
                 context: parsed["context"] || []
               }
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
end
