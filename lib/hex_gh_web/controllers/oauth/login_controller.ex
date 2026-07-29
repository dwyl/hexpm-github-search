defmodule HexGhWeb.OAuth.LoginController do
  use HexGhWeb, :controller

  def show(conn, _params) do
    return_to = conn.query_params["return_to"] || "/"
    render(conn, :login, return_to: return_to)
  end

  def create(conn, %{"username" => username, "password" => password} = params) do
    return_to = params["return_to"] || "/"
    admin_username = Application.get_env(:hex_gh, :mcp_admin_user)
    admin_password_hash = Application.get_env(:hex_gh, :mcp_admin_password_hash)

    if username == admin_username && Argon2.verify_pass(password, admin_password_hash) do
      conn
      |> put_session(:user_sub, "admin")
      |> redirect(to: return_to)
    else
      Argon2.no_user_verify()

      conn
      |> put_flash(:error, "Invalid credentials")
      |> render(:login, return_to: return_to)
    end
  end
end
