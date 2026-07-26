defmodule HexGh.Telegram.Handler do
  @moduledoc """
  Processes incoming Telegram webhook updates (text and voice messages).

  Pipeline execution is dispatched via Task.Supervisor to return 200 OK
  to Telegram immediately. This is necessary because the AI pipeline takes
  4-15 seconds, and Telegram retries webhooks that don't respond within ~10s,
  which would cause duplicate message processing.
  """

  require Logger

  alias HexGh.Agent.Pipeline
  alias HexGh.Telegram

  def on_update(%{"message" => %{"text" => text, "chat" => %{"id" => chat_id}}}) do
    Task.Supervisor.start_child(HexGh.TaskSupervisor, fn ->
      reply =
        format_result(Pipeline.run(%{text: text, is_audio: false}, user_id: "tg:#{chat_id}"))

      send_reply(chat_id, reply)
    end)

    :ok
  end

  def on_update(%{
        "message" => %{"voice" => %{"file_id" => file_id}, "chat" => %{"id" => chat_id}}
      }) do
    Task.Supervisor.start_child(HexGh.TaskSupervisor, fn ->
      reply = run_voice_pipeline(file_id, chat_id)
      send_reply(chat_id, reply)
    end)

    :ok
  end

  def on_update(update) do
    Logger.warning("Unhandled Telegram update: #{inspect(Map.keys(update))}")
    :ok
  end

  defp run_voice_pipeline(file_id, chat_id) do
    case Telegram.get_file_url(file_id) do
      {:ok, audio_url} ->
        format_result(Pipeline.run(%{text: audio_url, is_audio: true}, user_id: "tg:#{chat_id}"))

      {:error, reason} ->
        Logger.error("get_file_url failed: #{inspect(reason)}")
        "Sorry, I could not retrieve your voice message."
    end
  end

  defp format_result({:ok, response}), do: response
  defp format_result({:error, :rate_limited}), do: "Rate limit exceeded. Please wait a moment."

  defp format_result({:error, reason}) do
    Logger.error("Pipeline error: #{inspect(reason)}")
    "Something went wrong. Please try again."
  end

  defp send_reply(chat_id, reply) do
    case Telegram.send_message(chat_id, reply) do
      {:ok, _} -> :ok
      {:error, err} -> Logger.error("Telegram send failed: #{inspect(err)}")
    end
  end
end
