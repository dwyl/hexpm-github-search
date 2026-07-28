defmodule HexGhWeb.Plugs.MCPAuth do
  @moduledoc """
  Bearer token authentication for the public MCP endpoint.
  Checks Authorization header against the MCP_API_KEY env var.
  When MCP_API_KEY is not set, authentication is disabled (open access).
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Logger.info("MCP request: #{conn.method} #{conn.request_path} auth=#{has_auth_header?(conn)}")

    case Application.get_env(:hex_gh, :mcp_api_key) do
      nil -> conn
      expected_key -> verify_bearer(conn, expected_key)
    end
  end

  defp has_auth_header?(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> _] -> "bearer"
      [_] -> "other"
      [] -> "none"
    end
  end

  defp verify_bearer(conn, expected_key) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 ->
        if Plug.Crypto.secure_compare(token, expected_key), do: conn, else: unauthorized(conn)

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
    |> halt()
  end
end
