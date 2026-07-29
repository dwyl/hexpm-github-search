defmodule HexGhWeb.Plugs.MCPPlug do
  @moduledoc """
  Wraps the Anubis MCP StreamableHTTP Plug with Bearer token authentication.
  """
  alias Anubis.Server.Transport.StreamableHTTP
  alias HexGhWeb.Plugs.MCPBearerAuth

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = MCPBearerAuth.call(conn, [])

    if conn.halted do
      conn
    else
      # Force JSON responses by stripping text/event-stream from Accept header,
      # and ensuring application/json is present so clients without explicit Accept headers work.
      conn = normalize_accept_header(conn)

      opts =
        StreamableHTTP.Plug.init(server: HexGh.MCP.Server)

      StreamableHTTP.Plug.call(conn, opts)
    end
  end

  defp normalize_accept_header(conn) do
    conn = strip_sse_accept(conn)
    accepts = Plug.Conn.get_req_header(conn, "accept")

    if accepts == [] or Enum.all?(accepts, &(&1 == "")) do
      %{conn | req_headers: replace_header(conn.req_headers, "accept", ["application/json"])}
    else
      conn
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
