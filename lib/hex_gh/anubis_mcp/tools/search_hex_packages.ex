defmodule HexGh.MCP.Tools.SearchHexPackages do
  @moduledoc "Search Hex.pm packages by keyword. Returns top results sorted by downloads."

  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response
  alias Anubis.MCP.Error
  alias HexGh.Tools.Hex

  schema do
    field(:query, {:required, :string}, description: "Search query for Hex.pm packages")
  end

  @impl true
  def execute(%{query: query}, frame) do
    case Hex.search_packages(query) do
      {:ok, json} ->
        {:reply,
         Response.tool()
         |> Response.text(json), frame}

      {:error, reason} ->
        {:error, Error.execution(to_string(reason)), frame}
    end
  end
end
