defmodule HexGhWeb.Plugs.MCPSSE do
  @moduledoc """
  In-process SSE handler for the MCP endpoint.

  Bandit requires chunk writes from the connection-owning process.
  ExMCP's default SSEHandler spawns a GenServer which breaks this.
  This plug intercepts SSE GET requests and uses ExMCP.Server.SSESession.run_sse_loop/3
  to handle SSE in-process, forwarding POST/DELETE to ExMCP.HttpPlug.
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  alias ExMCP.Server.SSESession

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET"} = conn, opts) do
    accepts_sse =
      conn
      |> get_req_header("accept")
      |> Enum.any?(&String.contains?(&1, "text/event-stream"))

    if accepts_sse do
      handle_sse(conn)
    else
      forward_to_ex_mcp(conn, opts)
    end
  end

  def call(conn, opts) do
    forward_to_ex_mcp(conn, opts)
  end

  defp handle_sse(conn) do
    session_id = generate_session_id()

    # Initialize SSESession ETS table if needed
    SSESession.init()

    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("mcp-session-id", session_id)
      |> send_chunked(200)

    # Send connected event from this process (Bandit-safe)
    case chunk(conn, "event: connected\ndata: #{Jason.encode!(%{session_id: session_id})}\n\n") do
      {:ok, conn} ->
        Logger.info("MCP SSE connected: session=#{session_id}")

        # Register this process as the SSE stream for the session
        SSESession.register_sse_stream(session_id)

        # Block in ExMCP's SSE loop (handles {:sse_send, data} messages in-process)
        conn = SSESession.run_sse_loop(conn, session_id, idle_timeout: 600_000)

        SSESession.cleanup(session_id)
        Logger.info("MCP SSE disconnected: session=#{session_id}")
        conn

      {:error, reason} ->
        Logger.error("MCP SSE connect failed: #{inspect(reason)}")
        conn
    end
  end

  defp forward_to_ex_mcp(conn, opts) do
    ExMCP.HttpPlug.call(conn, ExMCP.HttpPlug.init(opts))
  end

  defp generate_session_id do
    "sse_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end
end
