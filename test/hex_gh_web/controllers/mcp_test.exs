defmodule HexGhWeb.MCPTest do
  use HexGhWeb.ConnCase

  describe "MCP endpoint auth" do
    test "rejects requests without Bearer token when MCP_API_KEY is set", %{conn: conn} do
      Application.put_env(:hex_gh, :mcp_api_key, "test-secret")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/mcp",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            params: %{
              "protocolVersion" => "2024-11-05",
              "clientInfo" => %{"name" => "test", "version" => "1.0"}
            },
            id: 1
          })
        )

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    after
      Application.delete_env(:hex_gh, :mcp_api_key)
    end

    test "rejects requests with wrong Bearer token", %{conn: conn} do
      Application.put_env(:hex_gh, :mcp_api_key, "test-secret")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer wrong-token")
        |> post(
          "/mcp",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            params: %{
              "protocolVersion" => "2024-11-05",
              "clientInfo" => %{"name" => "test", "version" => "1.0"}
            },
            id: 1
          })
        )

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    after
      Application.delete_env(:hex_gh, :mcp_api_key)
    end

    test "accepts requests with correct Bearer token", %{conn: conn} do
      Application.put_env(:hex_gh, :mcp_api_key, "test-secret")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer test-secret")
        |> post(
          "/mcp",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            params: %{
              "protocolVersion" => "2024-11-05",
              "clientInfo" => %{"name" => "test", "version" => "1.0"}
            },
            id: 1
          })
        )

      assert %{"result" => %{"capabilities" => _}} = json_response(conn, 200)
    after
      Application.delete_env(:hex_gh, :mcp_api_key)
    end

    test "accepts requests with raw token without Bearer prefix", %{conn: conn} do
      Application.put_env(:hex_gh, :mcp_api_key, "test-secret")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "test-secret")
        |> post(
          "/mcp",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            params: %{
              "protocolVersion" => "2024-11-05",
              "clientInfo" => %{"name" => "test", "version" => "1.0"}
            },
            id: 1
          })
        )

      assert %{"result" => %{"capabilities" => _}} = json_response(conn, 200)
    after
      Application.delete_env(:hex_gh, :mcp_api_key)
    end

    test "allows requests when MCP_API_KEY is not configured", %{conn: conn} do
      Application.delete_env(:hex_gh, :mcp_api_key)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/mcp",
          Jason.encode!(%{
            jsonrpc: "2.0",
            method: "initialize",
            params: %{
              "protocolVersion" => "2024-11-05",
              "clientInfo" => %{"name" => "test", "version" => "1.0"}
            },
            id: 1
          })
        )

      assert %{"result" => %{"capabilities" => _}} = json_response(conn, 200)
    end
  end

  describe "MCP tools/list" do
    test "returns only public tools", %{conn: conn} do
      Application.delete_env(:hex_gh, :mcp_api_key)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/mcp",
          Jason.encode!(%{jsonrpc: "2.0", method: "tools/list", params: %{}, id: 2})
        )

      %{"result" => %{"tools" => tools}} = json_response(conn, 200)
      tool_names = Enum.map(tools, & &1["name"])

      assert "search_hex_packages" in tool_names
      assert "search_github_issues" in tool_names
      refute "save_memory" in tool_names
      refute "out_of_scope" in tool_names
    end
  end
end
