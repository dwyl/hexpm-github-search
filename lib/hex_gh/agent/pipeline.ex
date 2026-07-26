defmodule HexGh.Agent.Pipeline do
  @moduledoc """
  Entry point that normalizes input before the agent pipeline.

  Acts as a switch: text input is passed directly to `Agent.process_query/2`,
  while audio input is first transcribed to text via the LLM transcriber
  (Mistral Voxtral) then forwarded to the same
  query pipeline.
  """

  alias HexGh.Agent
  alias HexGh.AI.Transcriber

  def run(input, opts \\ [])

  def run(%{text: text, is_audio: false}, opts) do
    Agent.process_query(text, opts)
  end

  def run(%{text: audio_url, is_audio: true}, opts) do
    case Transcriber.transcribe(audio_url) do
      {:ok, transcript} ->
        Agent.process_query(transcript, opts)

      {:error, reason} ->
        {:error, {:transcription_failed, reason}}
    end
  end
end
