defmodule HexGhWeb.OAuth.AuthorizeController do
  use HexGhWeb, :controller

  @behaviour Boruta.Oauth.AuthorizeApplication

  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner

  def authorize(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        redirect_to_login(conn)

      %ResourceOwner{} = resource_owner ->
        Boruta.Oauth.authorize(conn, resource_owner, __MODULE__)
    end
  end

  @impl true
  def preauthorize_success(conn, _response) do
    # Auto-approve for single-user setup
    authorize(conn, conn.params)
  end

  @impl true
  def preauthorize_error(conn, %Error{} = error) do
    authorize_error(conn, error)
  end

  @impl true
  def authorize_success(conn, %AuthorizeResponse{} = response) do
    redirect_uri = AuthorizeResponse.redirect_to_url(response)
    redirect(conn, external: redirect_uri)
  end

  @impl true
  def authorize_error(conn, %Error{format: format} = error) when not is_nil(format) do
    redirect_uri = Error.redirect_to_url(error)
    redirect(conn, external: redirect_uri)
  end

  def authorize_error(conn, %Error{status: status, error: error, error_description: description}) do
    conn
    |> put_status(status_code(status))
    |> json(%{error: error, error_description: description})
  end

  defp redirect_to_login(conn) do
    query = URI.encode_query(conn.query_params)
    return_to = "/oauth/authorize?#{query}"

    redirect(conn, to: "/oauth/login?return_to=#{URI.encode_www_form(return_to)}")
  end

  defp status_code(:bad_request), do: 400
  defp status_code(:unauthorized), do: 401
  defp status_code(:internal_server_error), do: 500
  defp status_code(status) when is_atom(status), do: Plug.Conn.Status.code(status)
end
