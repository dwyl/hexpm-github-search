defmodule HexGhWeb.Plugs.MCPPlug do
  @moduledoc false

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: [".well-known" | _]} = conn, _opts) do
    conn
    |> Plug.Conn.send_resp(404, "Not Found")
    |> Plug.Conn.halt()
  end

  def call(conn, _opts) do
    opts =
      Anubis.Server.Transport.StreamableHTTP.Plug.init(
        server: HexGh.MCP.Server,
        force_json_responses: true
      )

    Anubis.Server.Transport.StreamableHTTP.Plug.call(conn, opts)
  end
end
