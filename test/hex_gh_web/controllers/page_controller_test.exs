defmodule HexGhWeb.PageControllerTest do
  use HexGhWeb.ConnCase

  test "GET / renders the chat LiveView", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "chat"
  end
end
