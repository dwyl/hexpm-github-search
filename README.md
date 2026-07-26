# HexGh

## Project scope

Lightweight Elixir MCP Orchestrator with Long-Term Memory with natural language interaction via LLM.

## Overview

Build a lightweight, database-less Elixir Phoenix application that acts as a personalized AI assistant interface.
The application provides two interaction entry points (a web chat UI and a Telegram webhook) to process natural language queries.
It routes user intent through an **ExMCP** server module using `ministral-small-latest` via the Mistral API (`Req`) to call GitHub and Hex.pm endpoints, sanitizing payloads and returning clean Markdown answers.

Basically two calls:

- looking for `ical`is hexpm? use hexpm searhc capability: `curl -s "<https://hex.pm/api/packages?search=ical>`
- looking for `ical` in my repos? use Github search capability: `gh api search/issues -X GET -f q="org:dwyl ical`

Long-term user knowledge, preferences, and notes are stored locally in SQLite using vector embeddings (`mistral-embed` via `sqlite-vec`) and injected into the prompt before tool execution (Hybrid RAG + Tool Calling).

## Architectural Constraints

- **Framework:** Phoenix (LiveView enabled).
- **Telegram** via {:telegex, "~> 1.8"}. Check the repo located at "../crm_reactor".
- **HTTP Client:** Use `Req` exclusively for all HTTP requests (Mistral API, GitHub API, Hex.pm API).
- **MCP Integration:** Use `ex_mcp` to define tool schemas and route execution natively.
- **Local Vector Storage:** Use `exqlite` with `sqlite-vec` for fast, local 1024-dimensional vector similarity searches.
- **Models:**
  - Intent & Synthesis: `ministral-small-latest` via Mistral `/v1/chat/completions` REST API.
  - Embeddings: `mistral-embed` via Mistral `/v1/embeddings` REST API (1024-dim floats).
- **Rate limiting** of LLM calls {:hammer, "~> 6.2"}

## System Architecture & Interaction Flow

```txt
graph TD
    %% Define Entry Points
    Entry_LiveView[Phoenix LiveView UI <br/> (http://localhost:4000)]
    Entry_Telegram[Telegram Webhook Route <br/> (/webhook/telegram)]

    %% Orchestrator
    Orchestrator[Orchestrator Module <br/> (MyApp.Agent)]

    %% Define Steps within Orchestrator and related Modules
    Step1_Prefetch[1. Pre-Fetch Memory (RAG Pass)<br/>- Embed prompt via mistral-embed<br/>- Query sqlite-vec for top 3 matching facts]
    MCPServer_A[ExMCP Server Module <br/> (MyApp.MCPServer)]
    Step2_ToolDefs[2. Fetch tool definitions & Send<br/>[System Context + Prompt + Tool Schemas]]
    Mistral_Request[Mistral API Endpoint <br/> (ministral-small-latest)]

    %% Mistral Decision Logic
    Mistral_Decision{Analyze Response}
    CaseA[Case A: Direct Text]
    CaseB[Case B: "tool_calls" returned]
    Return_Direct[Return to UI / Telegram]

    %% Tool Dispatch
    Step3_Dispatch[3. Dispatch call_tool]
    MCPServer_B[ExMCP Server Module <br/> (handle_tool_call/3)]
    Match_GitHub{Pattern Match: GitHub Issues}
    Match_Hex{Pattern Match: Hex Packages}
    Match_Save{Pattern Match: Save Memory}

    %% Concrete Tools
    Tool_GitHub[search_github_issues<br/>- Req -> GitHub REST<br/>- Strip ~85% JSON noise]
    Tool_Hex[search_hex_packages<br/>- Req -> Hex.pm REST<br/>- Strip ~85% JSON noise]
    Tool_Save[save_memory<br/>- Auto-enrich from Hex<br/>- Embed context<br/>- Store raw fact + vec]

    %% Tool Outputs
    Step4_SendSanitized[4. Send Sanitized Output]
    Return_Ack[Return Acknowledgment <br/> to User / Telegram]

    %% Synthesis
    Mistral_Synthesis[Mistral API Endpoint <br/> (Synthesis Pass)]
    Step5_ReturnMarkdown[5. Return Clean Markdown]
    Final_Return[Return to UI / Telegram]

    %% Initial Connections
    Entry_LiveView -->|"(User Prompt)"| Orchestrator
    Entry_Telegram -->|"(User Prompt)"| Orchestrator

    %% Orchestrator Logic
    Orchestrator --> Step1_Prefetch
    Step1_Prefetch --> MCPServer_A
    MCPServer_A --> Step2_ToolDefs
    Step2_ToolDefs --> Mistral_Request
    Mistral_Request --> Mistral_Decision

    %% Mistral Decision Branching
    Mistral_Decision -->|"(No Tools Needed)"| CaseA
    Mistral_Decision -->|"(Tool Calls Present)"| CaseB
    CaseA --> Return_Direct

    %% Case B: Tool Usage
    CaseB --> Step3_Dispatch
    Step3_Dispatch --> MCPServer_B
    MCPServer_B --> Match_GitHub
    MCPServer_B --> Match_Hex
    MCPServer_B --> Match_Save

    Match_GitHub --> Tool_GitHub
    Match_Hex --> Tool_Hex
    Match_Save --> Tool_Save

    %% Post-Tool Routing
    Tool_GitHub --> Step4_SendSanitized
    Tool_Hex --> Step4_SendSanitized
    Tool_Save --> Return_Ack

    %% Synthesis & Final Output
    Step4_SendSanitized --> Mistral_Synthesis
    Mistral_Synthesis --> Step5_ReturnMarkdown
    Step5_ReturnMarkdown --> Final_Return

    %% Design Styling (Optional)
    style Orchestrator fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    style MCPServer_A fill:#e0f2f1,stroke:#004d40,stroke-width:1px;
    style MCPServer_B fill:#e0f2f1,stroke:#004d40,stroke-width:1px;
    style Mistral_Request fill:#fce4ec,stroke:#880e4f,stroke-width:2px;
    style Mistral_Synthesis fill:#fce4ec,stroke:#880e4f,stroke-width:2px;
    style Mistral_Decision fill:#fff9c4,stroke:#fbc02d,stroke-width:2px;
```

## Detailed Dual-Loop Specifications

### Loop 1: Querying (RAG + Live Tool Search)

1. **Memory Retrieval Pass:**
   - On incoming user prompt, call `https://api.mistral.ai/v1/embeddings` (`mistral-embed`) via `Req` to generate a 1024-dim float array.
   - Query local SQLite `memory_vectors` table using `sqlite-vec` cosine similarity distance to fetch the top 3 nearest `memories.id` matches.
   - Construct a System Context block:

     ```text
     <user_saved_knowledge>
     - [Saved May 2026]: ical is preferred over icalendar for recurrence handling
     </user_saved_knowledge>
     ```

2. **Intent Pass:**
   - Call `ExMCP.Client.list_tools/1` on `MyApp.MCPServer` to fetch available schemas (`search_github_issues`, `search_hex_packages`, `save_memory`).
   - POST the system prompt, user prompt, and tool schemas to Mistral's `/v1/chat/completions` endpoint.
3. **Execution & Sanitization:**
   - If Mistral returns `tool_calls`, execute the tool via `ExMCP.Client.call_tool/3`.
   - **`search_github_issues`:** Performs `Req.get("https://api.github.com/search/issues?q=...")` and strips node IDs/metadata down to `repo`, `number`, `title`, `state`, `url`, and `snippet` (~60 tokens/item).
   - **`search_hex_packages`:** Performs `Req.get("https://hex.pm/api/packages?search=...")` and strips down to `name`, `description`, `latest_version`, `updated_at`, `downloads_total`, and `url`.
4. **Synthesis Pass:**
   - Send the sanitized tool response back to Mistral to synthesize into clean Markdown formatted with direct links.

### Loop 2: Remembering (`save_memory` Tool with Auto-Enrichment)

1. **Tool Invocation:**
   - When user says e.g. *"Keep note: ex_mcp is great for building MCP servers in Elixir"*, Mistral returns `tool_calls` for `save_memory` with parameters `fact` and optional `package`.
2. **Auto-Enrichment (Elixir):**
   - If `package` parameter is present (or extracted from fact), perform `Req.get("https://hex.pm/api/packages/#{package}")` to fetch the official package `description`.
   - Build `enriched_context = "#{fact} | Package Details: #{description}"`.
3. **Vector Generation & Dual-Storage:**
   - Call `mistral-embed` via `Req` on `enriched_context` $\rightarrow$ returns 1024 float array.
   - Insert raw `fact` and `enriched_context` into `memories` table.
   - Insert vector into `memory_vectors` table linked by row ID.
4. **Return Acknowledgment:** Return simple text confirming the fact was saved.

### SQLite init

```elixir
defmodule MyApp.Memory do
  @moduledoc """
  Manages SQLite connection, sqlite-vec loading, embedding calls, and vector retrieval.
  """
  
  def init_db do
    {:ok, conn} = Exqlite.Sqlite3.open("priv/memory.db")
    
    # Enable sqlite-vec extension if present or create tables
    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fact TEXT NOT NULL,
        enriched_context TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    """)

    Exqlite.Sqlite3.execute(conn, """
    CREATE VIRTUAL TABLE IF NOT EXISTS memory_vectors USING vec0(
        embedding float[1024]
    );
    """)

    {:ok, conn}
  end

  def generate_embedding(text) do
    res = Req.post!("[https://api.mistral.ai/v1/embeddings](https://api.mistral.ai/v1/embeddings)",
      json: %{
        model: "mistral-embed",
        input: [text]
      },
      auth: {:bearer, System.fetch_env!("MISTRAL_API_KEY")}
    ).body

    hd(res["data"])["embedding"]
  end

  def save_fact(conn, fact, enriched_context) do
    vector = generate_embedding(enriched_context)
    
    # 1. Insert into memories
    {:ok, statement} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO memories (fact, enriched_context) VALUES (?, ?)")
    :ok = Exqlite.Sqlite3.bind(conn, statement, [fact, enriched_context])
    :done = Exqlite.Sqlite3.step(conn, statement)
    row_id = Exqlite.Sqlite3.last_insert_rowid(conn)
    Exqlite.Sqlite3.release(conn, statement)

    # 2. Insert into memory_vectors
    # Encode vector as binary float array for sqlite-vec
    vector_json = Jason.encode!(vector)
    {:ok, vec_stmt} = Exqlite.Sqlite3.prepare(conn, "INSERT INTO memory_vectors(rowid, embedding) VALUES (?, ?)")
    :ok = Exqlite.Sqlite3.bind(conn, vec_stmt, [row_id, vector_json])
    :done = Exqlite.Sqlite3.step(conn, vec_stmt)
    Exqlite.Sqlite3.release(conn, vec_stmt)

    :ok
  end

  def search_relevant_facts(conn, user_prompt, limit \\ 3) do
    prompt_vector = generate_embedding(user_prompt)
    vector_json = Jason.encode!(prompt_vector)

    query = """
    SELECT m.fact, m.created_at 
    FROM memory_vectors v
    JOIN memories m ON m.id = v.rowid
    WHERE v.embedding MATCH ?
    ORDER BY distance 
    LIMIT ?
    """

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, query)
    :ok = Exqlite.Sqlite3.bind(conn, stmt, [vector_json, limit])
    
    rows = fetch_all_rows(conn, stmt, [])
    Exqlite.Sqlite3.release(conn, stmt)

    Enum.map(rows, fn [fact, created_at] ->
      formatted_date = String.slice(to_string(created_at), 0, 7)
      "- [Saved #{formatted_date}]: #{fact}"
    end)
  end

  defp fetch_all_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> fetch_all_rows(conn, stmt, [row | acc])
      :done -> Enum.reverse(acc)
    end
  end
end
```

### ExMCP server

```elixir
defmodule MyApp.MCPServer do
  use ExMCP.Server

  deftool "search_github_issues" do
    meta do
      name "Search GitHub Issues"
      description "Searches GitHub issues across an organization or repository."
    end
    input_schema %{
      type: "object",
      properties: %{
        org: %{type: "string", description: "GitHub Organization (e.g. 'dwyl')"},
        query: %{type: "string", description: "Search query (e.g. 'Oban')"}
      },
      required: ["org", "query"]
    }
  end

  deftool "search_hex_packages" do
    meta do
      name "Search Hex Packages"
      description "Searches Hex.pm for Elixir packages by topic or keyword."
    end
    input_schema %{
      type: "object",
      properties: %{
        query: %{type: "string", description: "Search term (e.g. 'icalendar')"}
      },
      required: ["query"]
    }
  end

  deftool "save_memory" do
    meta do
      name "Save Memory"
      description "Saves a user fact, preference, or note into long-term memory."
    end
    input_schema %{
      type: "object",
      properties: %{
        fact: %{type: "string", description: "The core fact to save"},
        package: %{type: "string", description: "Optional associated Hex package name for enrichment"}
      },
      required: ["fact"]
    }
  end

  # Callback 1: GitHub Search
  @impl true
  def handle_tool_call("search_github_issues", %{"org" => org, "query" => query}, state) do
    url = "[https://api.github.com/search/issues?q=org:#](https://api.github.com/search/issues?q=org:#){org}+#{URI.encode(query)}"
    headers = [{"user-agent", "elixir-agent"}, {"accept", "application/vnd.github.v3+json"}]
    token = System.get_env("GITHUB_TOKEN")
    headers = if token, do: [{"authorization", "Bearer #{token}"} | headers], else: headers

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} ->
        results =
          body
          |> Map.get("items", [])
          |> Enum.take(5)
          |> Enum.map(fn item ->
            %{
              repo: item["repository_url"] |> String.split("/repos/") |> List.last(),
              number: item["number"],
              title: item["title"],
              state: item["state"],
              url: item["html_url"],
              snippet: String.slice(item["body"] || "", 0, 200)
            }
          end)

        {:ok, %{content: [%{type: "text", text: Jason.encode!(results)}]}, state}

      _ ->
        {:ok, %{content: [%{type: "text", text: "Failed to search GitHub."}]}, state}
    end
  end

  # Callback 2: Hex.pm Search
  @impl true
  def handle_tool_call("search_hex_packages", %{"query" => query}, state) do
    url = "[https://hex.pm/api/packages?search=#](https://hex.pm/api/packages?search=#){URI.encode(query)}"

    case Req.get(url, headers: [{"user-agent", "elixir-agent"}]) do
      {:ok, %{status: 200, body: pkgs}} when is_list(pkgs) ->
        results =
          pkgs
          |> Enum.take(5)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["name"],
              description: get_in(pkg, ["meta", "description"]),
              url: pkg["html_url"],
              version: pkg["latest_stable_version"] || pkg["latest_version"],
              updated_at: pkg["updated_at"],
              downloads_total: get_in(pkg, ["downloads", "all"])
            }
          end)

        {:ok, %{content: [%{type: "text", text: Jason.encode!(results)}]}, state}

      _ ->
        {:ok, %{content: [%{type: "text", text: "Failed to search Hex.pm."}]}, state}
    end
  end

  # Callback 3: Save Memory with Auto-Enrichment
  @impl true
  def handle_tool_call("save_memory", %{"fact" => fact} = args, state) do
    conn = state[:db_conn] || Process.get(:db_conn)
    pkg_name = Map.get(args, "package")

    enrichment_text =
      if pkg_name do
        case Req.get("[https://hex.pm/api/packages/#](https://hex.pm/api/packages/#){pkg_name}", headers: [{"user-agent", "elixir-agent"}]) do
          {:ok, %{status: 200, body: pkg}} ->
            desc = get_in(pkg, ["meta", "description"]) || ""
            "#{fact} | Package #{pkg_name}: #{desc}"
          _ -> fact
        end
      else
        fact
      end

    MyApp.Memory.save_fact(conn, fact, enrichment_text)
    {:ok, %{content: [%{type: "text", text: "Saved fact to long-term memory: '#{fact}'"}]}, state}
  end
end
```

### Agent orchestration

```elixir
defmodule MyApp.Agent do
  @doc """
  Runs Pre-fetch Memory RAG -> Mistral Intent Pass -> ExMCP Tool Call -> Synthesis Pass
  """
  def process_query(conn, user_prompt) do
    # 1. RAG Memory Pass
    relevant_facts = MyApp.Memory.search_relevant_facts(conn, user_prompt, 3)
    
    memory_context =
      if relevant_facts != [] do
        """
        <user_saved_knowledge>
        #{Enum.join(relevant_facts, "\n")}
        </user_saved_knowledge>
        """
      else
        ""
      end

    system_prompt = """
    You are a helpful Elixir assistant. Answer concisely and synthesize data into clean Markdown with direct links.
    #{memory_context}
    """

    # 2. ExMCP Client Connection
    Process.put(:db_conn, conn)
    {:ok, client} = ExMCP.start_client(server: MyApp.MCPServer)
    {:ok, %{tools: mcp_tools}} = ExMCP.Client.list_tools(client)
    formatted_tools = Enum.map(mcp_tools, &format_tool_for_mistral/1)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: user_prompt}
    ]

    # 3. Mistral Intent Call
    case call_mistral(messages, formatted_tools) do
      # Tool Call Requested
      %{"choices" => [%{"message" => %{"tool_calls" => [call | _]} = assistant_msg}]} ->
        tool_name = call["function"]["name"]
        tool_args = Jason.decode!(call["function"]["arguments"])

        {:ok, %{content: [%{text: tool_result_json}]}} = ExMCP.Client.call_tool(client, tool_name, tool_args)

        # 4. Synthesis Pass
        synthesis_messages = messages ++ [
          assistant_msg,
          %{
            role: "tool",
            tool_call_id: call["id"],
            name: tool_name,
            content: tool_result_json
          }
        ]

        case call_mistral(synthesis_messages, []) do
          %{"choices" => [%{"message" => %{"content" => markdown_response}}]} ->
            markdown_response
        end

      # Direct Answer
      %{"choices" => [%{"message" => %{"content" => direct_text}}]} ->
        direct_text
    end
  end

  defp call_mistral(messages, tools) do
    payload = %{model: "ministral-small-latest", messages: messages}
    payload = if tools != [], do: Map.put(payload, :tools, tools), else: payload

    Req.post!("[https://api.mistral.ai/v1/chat/completions](https://api.mistral.ai/v1/chat/completions)",
      json: payload,
      auth: {:bearer, System.fetch_env!("MISTRAL_API_KEY")}
    ).body
  end

  defp format_tool_for_mistral(tool) do
    %{
      type: "function",
      function: %{
        name: tool.name,
        description: tool.description,
        parameters: tool.inputSchema
      }
    }
  end
end
```

### Telegram webhook controller

check ../crm_reactor repo

### ChatLive UI

Simple.
