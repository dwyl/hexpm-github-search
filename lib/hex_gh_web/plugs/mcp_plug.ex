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
      # Force JSON responses by stripping text/event-stream from Accept header.
      # Anubis uses SSE streaming when it sees text/event-stream, but Caddy's
      # proxy timeout kills SSE connections before responses arrive.
      conn = strip_sse_accept(conn)

      opts =
        Anubis.Server.Transport.StreamableHTTP.Plug.init(server: HexGh.MCP.Server)

      Anubis.Server.Transport.StreamableHTTP.Plug.call(conn, opts)
    end
  end

  defp strip_sse_accept(conn) do
    updated =
      conn
      |> Plug.Conn.get_req_header("accept")
      |> Enum.map(fn value ->
        value
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&String.contains?(&1, "text/event-stream"))
        |> Enum.join(", ")
      end)
      |> Enum.reject(&(&1 == ""))

    %{conn | req_headers: replace_header(conn.req_headers, "accept", updated)}
  end

  defp replace_header(headers, key, []) do
    Enum.reject(headers, fn {k, _} -> k == key end)
  end

  defp replace_header(headers, key, values) do
    headers
    |> Enum.reject(fn {k, _} -> k == key end)
    |> Enum.concat(Enum.map(values, &{key, &1}))
  end
end
