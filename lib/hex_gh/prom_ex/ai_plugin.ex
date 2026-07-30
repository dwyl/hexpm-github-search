defmodule HexGh.PromEx.AIPlugin do
  @moduledoc "PromEx plugin for Mistral AI token and request metrics."
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      mistral_metrics(),
      knowledge_metrics()
    ]
  end

  defp mistral_metrics do
    Event.build(
      :hex_gh_ai_metrics,
      [
        counter(
          [:hex_gh, :ai, :mistral, :request, :total],
          event_name: [:hex_gh, :ai, :mistral, :request],
          tags: [:model, :path],
          description: "Total Mistral API requests count."
        ),
        sum(
          [:hex_gh, :ai, :mistral, :prompt_tokens, :total],
          event_name: [:hex_gh, :ai, :mistral, :request],
          measurement: :prompt_tokens,
          tags: [:model, :path],
          description: "Total Mistral prompt tokens consumed."
        ),
        sum(
          [:hex_gh, :ai, :mistral, :completion_tokens, :total],
          event_name: [:hex_gh, :ai, :mistral, :request],
          measurement: :completion_tokens,
          tags: [:model, :path],
          description: "Total Mistral completion tokens consumed."
        ),
        sum(
          [:hex_gh, :ai, :mistral, :total_tokens, :total],
          event_name: [:hex_gh, :ai, :mistral, :request],
          measurement: :total_tokens,
          tags: [:model, :path],
          description: "Total Mistral tokens consumed."
        )
      ]
    )
  end

  defp knowledge_metrics do
    Event.build(
      :hex_gh_knowledge_metrics,
      [
        counter(
          [:hex_gh, :knowledge, :decision, :total],
          event_name: [:hex_gh, :knowledge, :decision],
          tags: [:action, :strategy, :had_neighbors],
          description: "Knowledge base decision count by action type."
        ),
        distribution(
          [:hex_gh, :knowledge, :decision, :similarity],
          event_name: [:hex_gh, :knowledge, :decision],
          measurement: :top_similarity,
          tags: [:action, :had_neighbors],
          reporter_options: [buckets: [0.5, 0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95]],
          description: "Top neighbor similarity when making knowledge base decisions."
        )
      ]
    )
  end
end
