import Config

config :stdio_mcp,
  mistral_api_url: System.get_env("MISTRAL_API_URL", "https://api.mistral.ai/v1"),
  mistral_api_key: System.get_env("MISTRAL_API_KEY"),
  mistral_embed_model: System.get_env("MISTRAL_MODEL_EMBED", "mistral-embed"),
  mistral_chat_model: System.get_env("MISTRAL_MODEL_SMALL", "mistral-small-latest"),
  mistral_chat_model_large: System.get_env("MISTRAL_LARGE_MODEL", "mistral-medium-latest"),
  github_api_url: System.get_env("GITHUB_API_URL", "https://api.github.com"),
  github_token: System.get_env("GITHUB_TOKEN"),
  hex_api_url: System.get_env("HEX_API_URL", "https://hex.pm/api")

repo_overrides =
  [load_extensions: [SqliteVec.path()]] ++
    if(db_path = System.get_env("DATABASE_PATH"), do: [database: db_path], else: [])

config :stdio_mcp, StdioMcp.Repo, repo_overrides
