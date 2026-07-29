defmodule HexGh.AI.Transcriber do
  @moduledoc """
  Audio transcription via the Mistral API (Voxtral model).

  Accepts an audio URL (e.g. from a Telegram voice message), downloads the
  audio binary, and sends it as a multipart upload to Mistral's
  `/audio/transcriptions` endpoint using Req's built-in `form_multipart`.
  The transcription model is configured via `MISTRAL_TRANSCRIPTION_MODEL`
  (default: `voxtral-mini-latest`).
  """

  defp mistral_url do
    "#{Application.get_env(:hex_gh, :mistral_api_url, "https://api.mistral.ai/v1")}/audio/transcriptions"
  end

  defp transcription_model do
    Application.get_env(:hex_gh, :mistral_transcription_model, "voxtral-mini-latest")
  end

  def transcribe(audio_url) when is_binary(audio_url) do
    case Req.get(audio_url, receive_timeout: 15_000, finch: [name: HexGh.Finch]) do
      {:ok, %{status: 200, body: audio_data}} -> transcribe_audio(audio_data)
      {:ok, %{status: status}} -> {:error, {:download_failed, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp transcribe_audio(audio_data) do
    case Req.post(mistral_url(),
           form_multipart: [
             file: {audio_data, filename: "audio.ogg", content_type: "audio/ogg"},
             model: transcription_model()
           ],
           headers: [{"authorization", "Bearer #{mistral_api_key()}"}],
           receive_timeout: 30_000,
           finch: [name: HexGh.Finch]
         ) do
      {:ok, %{status: 200, body: %{"text" => text}}} ->
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp mistral_api_key do
    Application.get_env(:hex_gh, :mistral_api_key) ||
      raise "MISTRAL_API_KEY not configured"
  end
end
