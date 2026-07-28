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

  scope "/", HexGhWeb do
    pipe_through :browser

    live "/", ChatLive, :index
  end

  scope "/webhook", HexGhWeb do
    pipe_through :api

    post "/telegram", WebhookController, :telegram
  end

  pipeline :mcp do
    plug HexGhWeb.Plugs.MCPAuth
    plug HexGhWeb.Plugs.MCPRateLimit
  end

  # OAuth discovery (no auth) - must return JSON 404 so MCP clients
  # can detect "no OAuth" and fall back to Bearer token auth.
  scope "/.well-known" do
    pipe_through :api

    get "/*path", HexGhWeb.MCPHealthController, :not_found
  end

  # MCP health check and OAuth discovery (no auth required)
  scope "/mcp" do
    pipe_through :api

    get "/health", HexGhWeb.MCPHealthController, :health
    get "/.well-known/*path", HexGhWeb.MCPHealthController, :not_found
  end

  # MCP server for external clients (Claude Code, etc.)
  # Uses streamable HTTP (POST only) — no SSE needed.
  scope "/mcp" do
    pipe_through :mcp

    forward "/", ExMCP.HttpPlug,
      handler: HexGh.MCPServer.Public,
      server_info: %{name: "hexgh", version: "0.1.0"},
      sse_enabled: false,
      validate_origin: false,
      cors_enabled: true,
      allowed_origins: :any
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:hex_gh, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    # import Phoenix.LiveDashboard.Router

    # scope "/dev" do
    #   pipe_through :browser

    #   live_dashboard "/dashboard", metrics: HexGhWeb.Telemetry
    # end
  end
end
