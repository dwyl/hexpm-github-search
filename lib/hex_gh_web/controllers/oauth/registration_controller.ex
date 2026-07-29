defmodule HexGhWeb.OAuth.RegistrationController do
  use HexGhWeb, :controller

  @behaviour Boruta.Openid.DynamicRegistrationApplication

  @known_keys ~w(client_name redirect_uris grant_types response_types
    token_endpoint_auth_method jwks jwks_uri contacts client_uri scope
    supported_grant_types name confidential pkce)

  @one_year_seconds 60 * 60 * 24 * 365

  def register(conn, _params) do
    registration_params =
      conn.body_params
      |> Map.put_new("grant_types", ["authorization_code", "refresh_token"])
      |> Map.put_new("response_types", ["code"])
      |> Map.delete("token_endpoint_auth_method")
      |> atomize_known_keys()
      |> Map.put(:access_token_ttl, @one_year_seconds)
      |> Map.put(:refresh_token_ttl, @one_year_seconds)
      |> Map.put(:public_refresh_token, true)
      |> Map.put(:pkce, true)

    Boruta.Openid.register_client(conn, registration_params, __MODULE__)
  end

  defp atomize_known_keys(params) do
    Map.new(params, fn
      {key, value} when is_binary(key) and key in @known_keys ->
        {String.to_existing_atom(key), value}

      pair ->
        pair
    end)
  end

  @impl true
  def client_registered(conn, %Boruta.Oauth.Client{} = client) do
    body =
      %{
        client_id: client.id,
        client_secret: client.secret,
        client_id_issued_at: DateTime.to_unix(DateTime.utc_now()),
        client_secret_expires_at: 0,
        redirect_uris: client.redirect_uris,
        token_endpoint_auth_method: "none",
        grant_types: client.supported_grant_types,
        response_types: ["code"],
        client_name: client.name
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    conn
    |> put_status(:created)
    |> json(body)
  end

  @impl true
  def registration_failure(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_client_metadata", details: errors})
  end
end
