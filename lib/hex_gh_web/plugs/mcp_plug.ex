defmodule HexGhWeb.Plugs.MCPPlug do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    opts =
      Anubis.Server.Transport.StreamableHTTP.Plug.init(
        server: HexGh.MCP.Server,
        force_json_responses: true
      )

    Anubis.Server.Transport.StreamableHTTP.Plug.call(conn, opts)
  end
end
