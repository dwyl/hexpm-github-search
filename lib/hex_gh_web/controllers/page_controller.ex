defmodule HexGhWeb.PageController do
  use HexGhWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
