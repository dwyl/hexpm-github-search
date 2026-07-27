defmodule Mix.Tasks.Mcp.Server do
  @moduledoc "Starts the MCP server over stdio for use with Claude Code and other MCP clients."
  use Mix.Task

  @shortdoc "Runs the Hex.pm & GitHub MCP server over stdio"
  def run(_args) do
    Mix.Task.run("app.start")

    # Start ExMCP server listening on stdio
    {:ok, _pid} = ExMCP.Server.start_link(server: HexGh.MCPServer, transport: :stdio)

    # Keep the BEAM process alive
    Process.sleep(:infinity)
  end
end
