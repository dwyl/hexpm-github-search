defmodule HexGhWeb.CacheBodyReader do
  @moduledoc """
  Custom body reader that caches the raw body for /mcp paths.
  ExMCP.HttpPlug needs the raw body for JSON-RPC parsing,
  but Plug.Parsers consumes it before the router forwards to ExMCP.
  """

  def read_body(%Plug.Conn{request_path: "/mcp" <> _} = conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, Plug.Conn.assign(conn, :raw_body, body)}

      {:more, partial, conn} ->
        {:more, partial, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def read_body(conn, opts) do
    Plug.Conn.read_body(conn, opts)
  end
end
