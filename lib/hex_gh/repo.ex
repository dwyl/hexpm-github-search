defmodule HexGh.Repo do
  use Ecto.Repo, otp_app: :hex_gh, adapter: Ecto.Adapters.Postgres
end
