defmodule HexGh.AI.Transcriber do
  @moduledoc false

  defp mistral_url do
    "#{Application.get_env(:hex_gh, :mistral_api_url, "https://api.mistral.ai/v1")}/audio/transcriptions"
  end

  defp transcription_model do
    Application.get_env(:hex_gh, :mistral_transcription_model, "mistral-large-latest")
  end

  def transcribe(audio_url) when is_binary(audio_url) do
    case download_audio(audio_url) do
      {:ok, audio_data, content_type} ->
        provider = Application.get_env(:hex_gh, :whisper_provider, "mistral")
        transcribe_audio(provider, audio_data, content_type)

      {:error, _} = error ->
        error
    end
  end

  defp download_audio(url) do
    case Req.get(url, finch: HexGh.Finch) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type =
          headers
          |> Enum.find_value("audio/ogg", fn
            {"content-type", ct} -> ct
            _ -> false
          end)

        {:ok, body, content_type}

      {:ok, %{status: status}} ->
        {:error, {:download_failed, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transcribe_audio("mistral", audio_data, content_type) do
    multipart =
      Multipart.new()
      |> Multipart.add_part(Multipart.Part.text_field("model", transcription_model()))
      |> Multipart.add_part(
        Multipart.Part.file_content_field("file", audio_data, "audio.ogg",
          content_type: content_type
        )
      )

    content_length = Multipart.content_length(multipart)
    body = Multipart.body_stream(multipart) |> Enum.to_list() |> IO.iodata_to_binary()

    case Req.post(mistral_url(),
           body: body,
           headers: [
             {"authorization", "Bearer #{mistral_api_key()}"},
             {"content-type", Multipart.content_type(multipart, "multipart/form-data")},
             {"content-length", to_string(content_length)}
           ],
           finch: HexGh.Finch
         ) do
      {:ok, %{status: 200, body: %{"text" => text}}} ->
        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transcribe_audio("local", audio_data, content_type) do
    whisper_url =
      Application.get_env(:hex_gh, :whisper_url) ||
        raise "WHISPER_URL not configured for local provider"

    multipart =
      Multipart.new()
      |> Multipart.add_part(
        Multipart.Part.file_content_field("file", audio_data, "audio.ogg",
          content_type: content_type
        )
      )

    content_length = Multipart.content_length(multipart)
    body = Multipart.body_stream(multipart) |> Enum.to_list() |> IO.iodata_to_binary()

    case Req.post(whisper_url,
           body: body,
           headers: [
             {"content-type", Multipart.content_type(multipart, "multipart/form-data")},
             {"content-length", to_string(content_length)}
           ],
           finch: HexGh.Finch
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
