defmodule HexGh.MCP.Server do
  @moduledoc false
  require Logger

  use Anubis.Server,
    name: "hexgh",
    version: "0.1.0",
    capabilities: [:tools]

  component(HexGh.MCP.Tools.SearchHexPackages)
  component(HexGh.MCP.Tools.SearchGithubIssues)
  component(HexGh.MCP.Tools.Remember)
  component(HexGh.MCP.Tools.Recall)

  @impl true
  def init(_client_info, frame) do
    compile_tools = __MODULE__.__components__(:tool) |> Enum.map(& &1.name)
    Logger.info("Anubis MCP.Server init — compile-time tools: #{inspect(compile_tools)}")
    {:ok, frame}
  end
end
