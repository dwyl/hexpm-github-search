defmodule HexGh.MCP.Tools.SearchDocsTest do
  use ExUnit.Case, async: true

  alias HexGh.MCP.Tools.SearchDocs
  alias HexGh.MCPServer

  describe "SearchDocs component" do
    test "execute/2 returns formatted tool response without error" do
      params = %{query: "plug cowboy connection", include_examples_only: false}
      frame = %{}

      assert {:reply, response, ^frame} = SearchDocs.execute(params, frame)
      assert %Anubis.Server.Response{} = response
    end
  end

  describe "MCPServer integration" do
    test "call_tool search_docs is registered and dispatches successfully" do
      assert {:ok, {results, _notices}} =
               MCPServer.call_tool("search_docs", %{
                 "query" => "phoenix router",
                 "include_examples_only" => false
               })

      assert is_list(results)
    end
  end
end
