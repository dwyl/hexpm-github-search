defmodule HexGhWeb.Plugs.MCPCORS do
  @moduledoc """
  CORS headers for MCP and OAuth endpoints.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%{method: "OPTIONS"} = conn, _opts) do
    conn
    |> put_cors_headers()
    |> send_resp(204, "")
    |> halt()
  end

  def call(conn, _opts) do
    put_cors_headers(conn)
  end

  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, DELETE, OPTIONS")
    |> put_resp_header(
      "access-control-allow-headers",
      "content-type, authorization, accept, mcp-session-id"
    )
    |> put_resp_header("access-control-expose-headers", "mcp-session-id")
    |> put_resp_header("access-control-max-age", "3600")
  end
end
