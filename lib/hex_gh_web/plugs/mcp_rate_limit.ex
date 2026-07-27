defmodule HexGhWeb.Plugs.MCPRateLimit do
  @moduledoc """
  Rate limiting plug for the public MCP endpoint.
  Uses client IP as the rate limit key.
  Limits configured in `config :hex_gh, :rate_limits, mcp: {window_ms, limit}`.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    config = Application.get_env(:hex_gh, :rate_limits)[:mcp]
    {window_ms, limit} = {config[:window_ms], config[:limit]}
    key = "mcp:#{client_ip(conn)}"

    case Hammer.check_rate(key, window_ms, limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "Rate limit exceeded. Try again later."}))
        |> halt()
    end
  end

  defp client_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
