import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/hex_gh start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :hex_gh, HexGhWeb.Endpoint, server: true
end

config :hex_gh, HexGhWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# AI and external service configuration
config :hex_gh,
  # Mistral AI
  mistral_api_url: System.get_env("MISTRAL_API_URL", "https://api.mistral.ai/v1"),
  mistral_api_key: System.get_env("MISTRAL_API_KEY"),
  mistral_chat_model: System.get_env("MISTRAL_CHAT_MODEL", "mistral-small-latest"),
  mistral_embed_model: System.get_env("MISTRAL_EMBED_MODEL", "mistral-embed"),
  mistral_embed_dimensions: String.to_integer(System.get_env("MISTRAL_EMBED_DIMENSIONS", "1024")),
  mistral_transcription_model:
    System.get_env("MISTRAL_TRANSCRIPTION_MODEL", "voxtral-mini-latest"),
  # External APIs
  github_api_url: System.get_env("GITHUB_API_URL", "https://api.github.com"),
  github_token: System.get_env("GITHUB_TOKEN"),
  hex_api_url: System.get_env("HEX_API_URL", "https://hex.pm/api"),
  # Storage
  memory_db_path: System.get_env("MEMORY_DB_PATH", "priv/memory.db"),
  sqlite_vec_path: System.get_env("SQLITE_VEC_PATH"),
  # RAG: discard memory results with cosine distance above this threshold
  memory_distance_threshold: String.to_float(System.get_env("MEMORY_DISTANCE_THRESHOLD", "0.65")),
  # MCP: optional Bearer token for public MCP endpoint (open access if unset)
  mcp_api_key: System.get_env("MCP_API_KEY")

# Telegram bot configuration (optional — bot starts only if token is set)
telegram_bot_token = System.get_env("TELEGRAM_BOT_TOKEN")
telegram_secret_token = System.get_env("TELEGRAM_SECRET_TOKEN")

if telegram_bot_token do
  unless telegram_secret_token do
    raise "TELEGRAM_SECRET_TOKEN must be set when TELEGRAM_BOT_TOKEN is configured"
  end

  config :telegex, token: telegram_bot_token

  config :hex_gh,
    telegram_secret_token: telegram_secret_token,
    telegram_webhook_url: System.get_env("TELEGRAM_WEBHOOK_URL")
end

# OAuth admin credentials (optional in dev, required in prod)
if mcp_admin_user = System.get_env("MCP_ADMIN_USER") do
  config :hex_gh,
    mcp_admin_user: mcp_admin_user,
    mcp_admin_password_hash:
      System.get_env("MCP_ADMIN_PASSWORD_HASH") ||
        raise("MCP_ADMIN_PASSWORD_HASH must be set when MCP_ADMIN_USER is configured")
end

if config_env() == :prod do
  # PostgreSQL for Boruta OAuth
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL is not set"

  config :hex_gh, HexGh.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :hex_gh, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :hex_gh, HexGhWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Boruta OAuth issuer
  oauth_issuer = "https://#{host}"
  config :hex_gh, oauth_issuer: oauth_issuer
  config :boruta, Boruta.Oauth, issuer: oauth_issuer

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :hex_gh, HexGhWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :hex_gh, HexGhWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
