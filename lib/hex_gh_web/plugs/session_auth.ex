defmodule HexGhWeb.Plugs.SessionAuth do
  @moduledoc """
  Loads the current user from the session for OAuth authorize flows.
  """

  import Plug.Conn
  alias Boruta.Oauth.ResourceOwner

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_sub) do
      "admin" ->
        admin_username = Application.get_env(:hex_gh, :mcp_admin_user)

        assign(conn, :current_user, %ResourceOwner{
          sub: "admin",
          username: admin_username
        })

      _ ->
        assign(conn, :current_user, nil)
    end
  end
end
