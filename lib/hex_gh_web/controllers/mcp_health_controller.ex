defmodule HexGhWeb.MCPHealthController do
  use HexGhWeb, :controller

  def health(conn, _params) do
    json(conn, %{status: "ok", server: "hexgh", version: "0.1.0"})
  end

  @doc """
  Returns OAuth Protected Resource Metadata (RFC 9728) indicating
  no authorization is required. This tells Claude Code's MCP client
  that the server accepts unauthenticated requests.
  """
  def oauth_protected_resource(conn, _params) do
    json(conn, %{
      resource: "https://hexgh.nlex.uk/mcp",
      bearer_methods_supported: [],
      scopes_supported: []
    })
  end

  def not_found(conn, _params) do
    conn
    |> put_status(404)
    |> json(%{error: "Not found"})
  end
end
