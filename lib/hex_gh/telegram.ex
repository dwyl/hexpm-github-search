defmodule HexGh.Telegram do
  @moduledoc false

  def send_message(chat_id, text) do
    Telegex.send_message(chat_id, text, parse_mode: "Markdown")
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
end
