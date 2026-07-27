defmodule HexGhWeb.MCPToolSelectionTest do
  @moduledoc """
  End-to-end test: given the public MCP tool schemas, does Mistral
  pick the correct tool for different user inputs?
  Requires MISTRAL_API_KEY.
  """
  use ExUnit.Case, async: true

  alias HexGh.AI.Mistral
  alias HexGh.MCPServer

  @moduletag :integration

  @tools MCPServer.public_tool_schemas()

  describe "LLM tool selection with public MCP tools" do
    test "picks search_hex_packages for a package search query" do
      messages = [
        %{role: "system", content: "You are a helpful assistant. Use the provided tools."},
        %{role: "user", content: "Find Elixir packages for JSON parsing"}
      ]

      assert {:ok, %{"tool_calls" => [tool_call | _]}} =
               Mistral.chat(messages, @tools, tool_choice: "any")

      assert %{"function" => %{"name" => "search_hex_packages", "arguments" => args}} = tool_call
      assert byte_size(args) > 0
    end

    test "picks search_github_issues for a GitHub issue query" do
      messages = [
        %{role: "system", content: "You are a helpful assistant. Use the provided tools."},
        %{role: "user", content: "Find open issues about LiveView in the phoenixframework org"}
      ]

      assert {:ok, %{"tool_calls" => [tool_call | _]}} =
               Mistral.chat(messages, @tools, tool_choice: "any")

      assert %{"function" => %{"name" => "search_github_issues", "arguments" => args}} = tool_call
      decoded = Jason.decode!(args)
      assert byte_size(decoded["org"]) > 0
      assert byte_size(decoded["query"]) > 0
    end

    test "picks search_hex_packages for a library recommendation query" do
      messages = [
        %{role: "system", content: "You are a helpful assistant. Use the provided tools."},
        %{role: "user", content: "What's the best Elixir HTTP client library?"}
      ]

      assert {:ok, %{"tool_calls" => [tool_call | _]}} =
               Mistral.chat(messages, @tools, tool_choice: "any")

      assert %{"function" => %{"name" => "search_hex_packages"}} = tool_call
    end

    test "does not pick any tool for an out-of-scope query" do
      messages = [
        %{role: "system", content: "You are a helpful assistant. Only use tools when relevant."},
        %{role: "user", content: "What time is it?"}
      ]

      assert {:ok, response} =
               Mistral.chat(messages, @tools, tool_choice: "auto")

      # LLM should respond with text content, not a tool call
      assert byte_size(response["content"]) > 0
      refute match?([_ | _], response["tool_calls"])
    end
  end
end
