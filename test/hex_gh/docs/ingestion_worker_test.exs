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

  describe "build_doc_items/3" do
    test "splits a long guide into multiple chunked doc items" do
      long_content = String.duplicate("This is a detailed section in a guide page. ", 200)

      item = %{
        "ref" => "guides/overview.html",
        "title" => "Overview Guide",
        "doc" => long_content,
        "type" => "guide"
      }

      items = IngestionWorker.build_doc_items("phoenix_live_view", "1.0.0", item)

      assert length(items) > 1
      first = Enum.at(items, 0)
      second = Enum.at(items, 1)

      assert first.signature == "Overview Guide - Part 1"

      assert first.hexdocs_url ==
               "https://hexdocs.pm/phoenix_live_view/1.0.0/guides/overview.html#part-1"

      assert second.signature == "Overview Guide - Part 2"

      assert second.hexdocs_url ==
               "https://hexdocs.pm/phoenix_live_view/1.0.0/guides/overview.html#part-2"
    end

    test "preserves function docs as a single doc item without chunking" do
      item = %{
        "ref" => "Phoenix.Component.html#form/1",
        "title" => "Phoenix.Component.form/1",
        "doc" => "Renders a form element for changesets or params.",
        "type" => "function"
      }

      items = IngestionWorker.build_doc_items("phoenix", "1.8.0", item)

      assert length(items) == 1
      doc = hd(items)
      assert doc.signature == "Phoenix.Component.form/1"
      assert doc.hexdocs_url == "https://hexdocs.pm/phoenix/1.8.0/Phoenix.Component.html#form/1"
    end
  end

  describe "extract_text_from_html/1" do
    test "strips HTML tags and script/style tags, decoding entities" do
      html = """
      <!DOCTYPE html>
      <html>
        <body>
          <main id="content">
            <h1>Guide &amp; Documentation</h1>
            <script>console.log("ignore me");</script>
            <style>body { color: red; }</style>
            <p>Welcome to <strong>HexGh</strong> guide.</p>
          </main>
        </body>
      </html>
      """

      text = IngestionWorker.extract_text_from_html(html)
      assert text =~ "Guide & Documentation"
      assert text =~ "Welcome to HexGh guide."
      refute text =~ "console.log"
      refute text =~ "color: red"
    end
  end
end
