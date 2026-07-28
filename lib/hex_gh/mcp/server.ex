defmodule HexGh.MCP.Server do
  @moduledoc false

  use Anubis.Server,
    name: "hexgh",
    version: "0.1.0",
    capabilities: [:tools]

  component(HexGh.MCP.Tools.SearchHexPackages)
  component(HexGh.MCP.Tools.SearchGithubIssues)

  @impl true
  def init(_client_info, frame) do
    {:ok, frame}
  end
end
