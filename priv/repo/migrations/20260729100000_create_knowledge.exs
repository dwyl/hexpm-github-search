defmodule HexGh.Repo.Migrations.CreateKnowledge do
  use Ecto.Migration

  def up do
    # execute "CREATE EXTENSION IF NOT EXISTS vector"

    create table(:knowledge) do
      add(:kind, :text, null: false)
      add(:title, :text, null: false)
      add(:content, :text, null: false)
      add(:metadata, :jsonb, default: "{}")
      add(:embedding, :vector, size: 1024)

      timestamps()
    end

    create(index(:knowledge, [:kind]))
  end

  def down do
    drop(table(:knowledge))
    execute("DROP EXTENSION IF EXISTS vector")
  end
end
