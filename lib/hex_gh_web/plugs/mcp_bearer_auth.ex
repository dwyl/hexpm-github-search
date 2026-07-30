defmodule HexGhWeb.Plugs.MCPBearerAuth do
  @moduledoc """
  Validates OAuth Bearer tokens on MCP requests.
  Falls back to static MCP_API_KEY if configured.
  Returns 401 with WWW-Authenticate header on failure.
  """

  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    case authenticate(conn) do
      {:ok, :static} ->
        assign(conn, :oauth_token, %{static: true})

      {:ok, %{expires_at: expires_at} = token} ->
        if expires_at > :os.system_time(:second) do
          assign(conn, :oauth_token, token)
        else
          Logger.debug("Bearer auth failed: token expired")
          unauthorized(conn)
        end

      {:error, reason} ->
        Logger.debug("Bearer auth failed: #{reason}")
        unauthorized(conn)
    end
  end

  defp authenticate(conn) do
    # Try header authentication first (supporting optional "Bearer " prefix)
    case get_req_header(conn, "authorization") do
      [header_val] when header_val != "" ->
        token_value = String.replace_prefix(header_val, "Bearer ", "")
        verify_token(token_value)

      _ ->
        # Fallback to query parameter "token" or "access_token"
        case conn.query_params["token"] || conn.query_params["access_token"] do
          token_value when is_binary(token_value) and token_value != "" ->
            verify_token(token_value)

          _ ->
            if static_key_configured?() do
              {:error, "no authorization header or query token"}
            else
              {:ok, :static}
            end
        end
    end
  end

  defp static_key_configured? do
    case Application.get_env(:hex_gh, :mcp_api_key) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp verify_token(token_value) do
    if static_token_match?(token_value) do
      {:ok, :static}
    else
      if Process.whereis(HexGh.Repo) do
        try do
          case Boruta.Config.access_tokens().get_by(value: token_value) do
            %{} = token -> {:ok, token}
            nil -> {:error, "token not found"}
          end
        rescue
          _ -> {:error, "token not found"}
        catch
          :exit, _ -> {:error, "token not found"}
        end
      else
        {:error, "token not found"}
      end
    end
  end

  defp static_token_match?(token_value) do
    case Application.get_env(:hex_gh, :mcp_api_key) do
      nil -> false
      "" -> false
      key -> Plug.Crypto.secure_compare(token_value, key)
    end
  end

  defp unauthorized(conn) do
    issuer = Application.get_env(:hex_gh, :oauth_issuer)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header(
      "www-authenticate",
      "Bearer resource_metadata=\"#{issuer}/.well-known/oauth-protected-resource\""
    )
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end
