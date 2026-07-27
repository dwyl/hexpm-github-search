defmodule HexGh.Integration.PipelineTest do
  use ExUnit.Case

  alias HexGh.Agent.Pipeline
  alias HexGh.AI.Mistral
  alias HexGh.MCPServer
  alias HexGh.Memory

  @moduletag :integration
  @moduletag timeout: 120_000

  setup_all do
    # Wipe the test memory DB and let the supervisor restart Memory cleanly
    db_path = Application.get_env(:hex_gh, :memory_db_path, "priv/test_memory.db")
    File.rm(db_path)
    Supervisor.terminate_child(HexGh.Supervisor, Memory)
    Supervisor.restart_child(HexGh.Supervisor, Memory)
    :ok
  end

  describe "Mistral API:" do
    test "embed/1 returns a 1024-dim vector" do
      assert {:ok, embedding} = Mistral.embed("Elixir is a functional language")
      refute embedding == []
      assert length(embedding) == 1024
      assert Enum.all?(embedding, &is_float/1)
    end

    test "chat/3 returns a response" do
      messages = [%{role: "user", content: "Say hello in one word"}]
      assert {:ok, %{"content" => content}} = Mistral.chat(messages)
      assert byte_size(content) != 0
      assert String.length(content) > 0
    end

    test "chat/3 with tools returns a tool call" do
      messages = [
        %{role: "system", content: "You must use the provided tools."},
        %{role: "user", content: "Search for phoenix on hex.pm"}
      ]

      tools = MCPServer.tool_schemas()

      assert {:ok, %{"tool_calls" => [tool_call | _]}} =
               Mistral.chat(messages, tools, tool_choice: "any")

      assert %{"function" => %{"name" => name}} = tool_call
      assert name in ["search_hex_packages", "search_github_issues", "save_memory"]
    end
  end

  describe "Memory (sqlite-vec):" do
    test "save_fact/3 and search_relevant/2 roundtrip" do
      {:ok, embedding} = Mistral.embed("Phoenix is a web framework for Elixir")

      assert {:ok, id} =
               Memory.save_fact("test", "Phoenix is a web framework for Elixir", embedding)

      assert is_integer(id)

      {:ok, query_embedding} = Mistral.embed("Elixir web framework")
      assert {:ok, results} = Memory.search_relevant(query_embedding, 3)
      refute results == []
      assert hd(results).content =~ "Phoenix"
    end
  end

  describe "Tool dispatch:" do
    test "search_hex_packages returns results" do
      assert {:ok, json} =
               MCPServer.call_tool("search_hex_packages", %{"query" => "oban"})

      results = Jason.decode!(json)
      refute results == []
      assert Enum.any?(results, fn r -> r["name"] =~ "oban" end)
    end

    test "search_github_issues returns results" do
      assert {:ok, json} =
               MCPServer.call_tool("search_github_issues", %{
                 "org" => "dwyl",
                 "query" => "pattern matching"
               })

      results = Jason.decode!(json)
      refute results == []
      assert hd(results)["html_url"] =~ "github.com"
    end

    test "save_memory with package enrichment" do
      assert {:ok, msg} =
               MCPServer.call_tool("save_memory", %{
                 "fact" => "Phoenix is great for real-time apps",
                 "package" => "phoenix"
               })

      assert msg =~ "Saved to memory"
    end

    test "unknown tool returns error" do
      assert {:error, "Unknown tool: nope"} = MCPServer.call_tool("nope", %{})
    end
  end

  describe "Full agent pipeline" do
    test "process_query finds hex packages" do
      assert {:ok, response} =
               HexGh.Agent.process_query("find a package to manage icalendar data")

      assert byte_size(response) != 0
      assert String.length(response) > 50
    end

    test "process_query searches github issues" do
      assert {:ok, response} =
               HexGh.Agent.process_query(
                 "Find issues about LiveView in the phoenixframework org on GitHub"
               )

      assert byte_size(response) != 0
      assert String.length(response) > 50
    end

    test "build_memory_context retrieves relevant facts into the prompt" do
      # Save 4 facts — only some are relevant to "HTTP server"
      facts = [
        "Elixir's preferred HTTP server is Bandit",
        "Phoenix is the main web framework in the Elixir ecosystem",
        "Ecto handles database queries and migrations",
        "ExUnit is the built-in testing framework for Elixir"
      ]

      for fact <- facts do
        {:ok, emb} = Mistral.embed(fact)
        assert {:ok, _id} = Memory.save_fact("general", fact, emb)
      end

      # Query specifically for HTTP server — Bandit fact must surface
      assert {:ok, context} = HexGh.Agent.build_memory_context("what HTTP server does Elixir use")
      # dbg(context)
      assert context =~ "<user_saved_knowledge>"
      assert context =~ "Bandit"
    end

    test "process_query with RAG context influences the response" do
      # Ensure the fact exists (idempotent — may already be saved by prior test)
      {:ok, emb} = Mistral.embed("Elixir's preferred HTTP server is Bandit")
      Memory.save_fact("general", "Elixir's preferred HTTP server is Bandit", emb)

      assert {:ok, response} =
               HexGh.Agent.process_query("find Elixir packages for HTTP servers")

      dbg(response)
      assert response =~ ~r/[Bb]andit/
    end

    test "out_of_scope query returns canned response without synthesis" do
      assert {:ok, response} = HexGh.Agent.process_query("what time is it?")
      assert response =~ "can't process this"
    end

    test "Pipeline.run delegates to process_query" do
      assert {:ok, response} =
               Pipeline.run(%{
                 text: "What Elixir packages exist for WebSockets?",
                 is_audio: false
               })

      assert byte_size(response) != 0
      assert String.length(response) > 50
    end
  end
end
