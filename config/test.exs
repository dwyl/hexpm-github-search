import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hex_gh, HexGhWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "CFeLzvD7Ksyi4LYviwz7r97rPSuItNUhkGCpMBYZBF8IUtBJ44XP/8hMt0ujYbDZ",
  server: false

# Use a separate memory DB for tests (wiped before each run)
config :hex_gh, memory_db_path: "priv/test_memory.db"

# Test database
config :hex_gh, HexGh.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "hex_gh_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# OAuth test defaults
config :hex_gh,
  oauth_issuer: "http://localhost:4002",
  mcp_admin_user: "admin",
  mcp_admin_password_hash: "$argon2id$v=19$m=65536,t=3,p=4$placeholder"

config :boruta, Boruta.Oauth, issuer: "http://localhost:4002"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
