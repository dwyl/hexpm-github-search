defmodule HexGhWeb.Plugs.MCPApiKey do
  @moduledoc """
  Simple Bearer token authentication for the MCP endpoint.

  Checks `Authorization: Bearer <token>` against the configured `MCP_API_KEY`.
  If no key is configured, all requests are allowed (open access).
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:hex_gh, :mcp_api_key) do
      nil ->
        # No key configured — open access
        conn

      expected when is_binary(expected) and expected != "" ->
        with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
             true <- Plug.Crypto.secure_compare(token, expected) do
          conn
        else
          _ -> conn |> send_resp(401, "unauthorized") |> halt()
        end

      _ ->
        conn
    end
  end
end
