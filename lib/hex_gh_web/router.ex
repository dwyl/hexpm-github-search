defmodule HexGhWeb.Router do
  use HexGhWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HexGhWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :oauth_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug HexGhWeb.Plugs.SessionAuth
  end

  pipeline :mcp do
    plug HexGhWeb.Plugs.MCPCORS
    plug HexGhWeb.Plugs.MCPRateLimit
  end

  scope "/", HexGhWeb do
    pipe_through :browser

    live "/", ChatLive, :index
  end

  scope "/webhook", HexGhWeb do
    pipe_through :api

    post "/telegram", WebhookController, :telegram
  end

  # Well-known metadata (no auth)
  scope "/.well-known", HexGhWeb.OAuth do
    pipe_through :api
    get "/oauth-protected-resource", WellKnownController, :protected_resource
    get "/oauth-authorization-server", WellKnownController, :authorization_server
  end

  # OAuth browser flow (session support for login + authorize)
  scope "/oauth", HexGhWeb.OAuth do
    pipe_through :oauth_browser
    get "/login", LoginController, :show
    post "/login", LoginController, :create
    get "/authorize", AuthorizeController, :authorize
  end

  # OAuth API endpoints (no session needed)
  scope "/oauth", HexGhWeb.OAuth do
    pipe_through :api
    post "/token", TokenController, :token
    post "/register", RegistrationController, :register
    post "/revoke", RevokeController, :revoke
  end

  # MCP health check (no auth required)
  scope "/mcp" do
    get "/health", HexGhWeb.MCPHealthController, :health
  end

  # MCP server (protected by BearerAuth via MCPPlug)
  scope "/mcp" do
    pipe_through :mcp

    forward "/", HexGhWeb.Plugs.MCPPlug
  end
end
