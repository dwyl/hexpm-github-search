defmodule HexGh.Telegram do
  @moduledoc """
  Telegram API helpers — message sending, file URLs, and webhook registration.

  `register_webhook/1` is called on application startup (when `TELEGRAM_BOT_TOKEN`
  is configured) to register the webhook URL with Telegram. This is idempotent —
  Telegram overwrites the previous webhook on each call.
  """

  require Logger

  def send_message(chat_id, text) do
    Telegex.send_message(chat_id, text)
  end

  def get_file_url(file_id) do
    case Telegex.get_file(file_id) do
      {:ok, %{file_path: file_path}} ->
        token = Application.get_env(:telegex, :token)
        {:ok, "https://api.telegram.org/file/bot#{token}/#{file_path}"}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Registers the webhook URL with Telegram. Called on app startup.

  Requires `TELEGRAM_WEBHOOK_URL` (e.g. `https://your-tunnel.domain`).
  The webhook path `/webhook/telegram` is appended automatically.
  """
  def register_webhook(base_url) do
    url = "#{String.trim_trailing(base_url, "/")}/webhook/telegram"
    secret = Application.get_env(:hex_gh, :telegram_secret_token)

    case Telegex.set_webhook(url, secret_token: secret) do
      {:ok, true} ->
        Logger.info("Telegram webhook registered: #{url}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to register Telegram webhook: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
