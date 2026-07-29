defmodule HexGhWeb.OAuth.TokenController do
  use HexGhWeb, :controller

  @behaviour Boruta.Oauth.TokenApplication

  def token(conn, _params) do
    Boruta.Oauth.token(conn, __MODULE__)
  end

  @impl true
  def token_success(conn, %Boruta.Oauth.TokenResponse{} = response) do
    body =
      %{
        token_type: response.token_type,
        access_token: response.access_token,
        expires_in: response.expires_in,
        refresh_token: response.refresh_token,
        id_token: response.id_token
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(body)
  end

  @impl true
  def token_error(conn, %Boruta.Oauth.Error{
        status: status,
        error: error,
        error_description: description
      }) do
    conn
    |> put_status(status_code(status))
    |> json(%{error: error, error_description: description})
  end

  defp status_code(:bad_request), do: 400
  defp status_code(:unauthorized), do: 401
  defp status_code(:internal_server_error), do: 500
  defp status_code(status) when is_atom(status), do: Plug.Conn.Status.code(status)
end
