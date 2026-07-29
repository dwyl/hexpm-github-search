defmodule HexGh.Release do
  @moduledoc "Release tasks for running migrations outside Mix."
  @app :hex_gh

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def create_admin do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(HexGh.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
      end)
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
