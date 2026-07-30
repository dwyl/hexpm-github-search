defmodule HexGh.PromEx.AIPlugin do
  @moduledoc "PromEx plugin for Mistral AI token and request metrics."
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
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
end
