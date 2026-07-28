defmodule HexGh.MCP.Server do
  @moduledoc false
  require Logger

  use Anubis.Server,
    name: "hexgh",
    version: "0.1.0",
    capabilities: [:tools]

  component(HexGh.MCP.Tools.SearchHexPackages)
  component(HexGh.MCP.Tools.SearchGithubIssues)

  @impl true
  def init(_client_info, frame) do
    Logger.info("Anubis MCP.Server init: #{inspect(frame)}")
    {:ok, frame}
  end
end
