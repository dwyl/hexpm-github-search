# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :hex_gh,
  ecto_repos: [HexGh.Repo],
  generators: [timestamp_type: :utc_datetime]

config :hex_gh, HexGh.Repo, types: HexGh.PostgrexTypes

# Boruta OAuth 2.1
config :boruta, Boruta.Oauth,
  repo: HexGh.Repo,
  contexts: [
    resource_owners: HexGh.OAuth.ResourceOwners
  ],
  max_ttl: [
    access_token: 60 * 60 * 24 * 365,
    refresh_token: 60 * 60 * 24 * 365
  ]

# Configure the endpoint
config :hex_gh, HexGhWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HexGhWeb.ErrorHTML, json: HexGhWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HexGh.PubSub,
  live_view: [signing_salt: "efWCcj+I"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  hex_gh: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  hex_gh: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Hammer rate limiting
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 10, cleanup_interval_ms: 60_000]}

# Rate limits: window in ms, max requests per window
config :hex_gh, :rate_limits,
  agent: [window_ms: 60_000, limit: 20],
  mcp: [window_ms: 60_000, limit: 60]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
