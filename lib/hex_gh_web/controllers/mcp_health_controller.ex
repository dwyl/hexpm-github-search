defmodule HexGhWeb.MCPHealthController do
  use HexGhWeb, :controller

  def health(conn, _params) do
    json(conn, %{status: "ok", server: "hexgh", version: "0.1.0"})
  end
end
