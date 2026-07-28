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
    Logger.info("Anubis MCP.Server init")
    %Anubis.Server.Frame{tools: tools} = frame
    Logger.info("Anubis Init: tools: #{inspect(tools)}")
    {:ok, frame}
  end
end
