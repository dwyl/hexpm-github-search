defmodule HexGh.Docs.IngestionWorkerTest do
  use ExUnit.Case, async: true

  alias HexGh.Docs.IngestionWorker

  describe "parse_search_data_js/1" do
    test "parses searchData assignment format" do
      js = """
      var searchData = {"items":[{"ref":"Module.html","title":"Module","doc":"Description","type":"module"}]};
      """

      assert {:ok, data} = IngestionWorker.parse_search_data_js(js)
      assert %{"items" => [item]} = data
      assert item["title"] == "Module"
    end

    test "parses searchNodes assignment format" do
      js = """
      searchNodes = [{"ref":"Func.html","name":"func/1","doc":"Function doc","type":"function"}];
      """

      assert {:ok, data} = IngestionWorker.parse_search_data_js(js)
      assert %{"items" => [item]} = data
      assert item["name"] == "func/1"
    end

    test "parses sidebarNodes assignment format" do
      js = """
      sidebarNodes={"modules":[{"id":"Boruta.Oauth","title":"Boruta.Oauth","nodeGroups":[{"key":"functions","nodes":[{"id":"token/2","anchor":"token/2"}]}]}]};
      """

      assert {:ok, data} = IngestionWorker.parse_search_data_js(js)
      assert %{"items" => items} = data
      assert length(items) >= 2
    end
  end

  describe "extract_code_snippet/1" do
    test "extracts markdown elixir code block" do
      content = """
      Here is an example:

      ```elixir
      def hello do
        :world
      end
      ```

      End of example.
      """

      snippet = IngestionWorker.extract_code_snippet(content)
      assert snippet == "def hello do\n  :world\nend"
    end

    test "returns nil when no code block present" do
      assert is_nil(IngestionWorker.extract_code_snippet("Just text content without code."))
    end
  end
end
