defmodule HexGh.Repo.Migrations.AddOutdatedToKnowledge do
  use Ecto.Migration

  def up do
    alter table(:knowledge) do
      add :outdated, :boolean, default: false, null: false
    end

    create index(:knowledge, [:outdated])

    execute """
    CREATE INDEX IF NOT EXISTS knowledge_search_vector_active_idx 
    ON knowledge USING gin (search_vector) 
    WHERE (outdated = false);
    """

    execute """
    CREATE INDEX IF NOT EXISTS knowledge_embedding_active_hnsw_idx 
    ON knowledge USING hnsw (embedding vector_cosine_ops) 
    WHERE (outdated = false);
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS knowledge_embedding_active_hnsw_idx;"
    execute "DROP INDEX IF EXISTS knowledge_search_vector_active_idx;"
    drop_if_exists index(:knowledge, [:outdated])

    alter table(:knowledge) do
      remove :outdated
    end
  end
end
