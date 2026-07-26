defmodule HexGhWeb.WebhookController do
  use HexGhWeb, :controller

  alias HexGh.Telegram.Handler

  def telegram(conn, params) do
    secret = Application.get_env(:hex_gh, :telegram_secret_token)

    with [provided] <- get_req_header(conn, "x-telegram-bot-api-secret-token"),
         true <- is_binary(secret) and Plug.Crypto.secure_compare(provided, secret) do
      Handler.on_update(params)
      json(conn, %{ok: true})
    else
      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "unauthorized"})
    end
  end
end
