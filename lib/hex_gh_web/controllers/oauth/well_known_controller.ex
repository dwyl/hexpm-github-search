defmodule HexGhWeb.OAuth.WellKnownController do
  use HexGhWeb, :controller

  def protected_resource(conn, _params) do
    issuer = Application.get_env(:hex_gh, :oauth_issuer)

    json(conn, %{
      resource: "#{issuer}/mcp",
      authorization_servers: [issuer],
      scopes_supported: ["mcp:read"],
      bearer_methods_supported: ["header"]
    })
  end

  def authorization_server(conn, _params) do
    issuer = Application.get_env(:hex_gh, :oauth_issuer)

    json(conn, %{
      issuer: issuer,
      authorization_endpoint: "#{issuer}/oauth/authorize",
      token_endpoint: "#{issuer}/oauth/token",
      registration_endpoint: "#{issuer}/oauth/register",
      revocation_endpoint: "#{issuer}/oauth/revoke",
      response_types_supported: ["code"],
      response_modes_supported: ["query"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      revocation_endpoint_auth_methods_supported: ["none"],
      scopes_supported: ["mcp:read"]
    })
  end
end
