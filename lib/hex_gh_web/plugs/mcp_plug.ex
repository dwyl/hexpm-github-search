defmodule HexGhWeb.Plugs.MCPPlug do
  @moduledoc """
  Wraps the Anubis MCP StreamableHTTP Plug with Bearer token authentication.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = HexGhWeb.Plugs.MCPBearerAuth.call(conn, [])

    if conn.halted do
      conn
    else
      opts =
        Anubis.Server.Transport.StreamableHTTP.Plug.init(
          server: HexGh.MCP.Server,
          force_json_responses: true
        )

      Anubis.Server.Transport.StreamableHTTP.Plug.call(conn, opts)
    end
  end
end
