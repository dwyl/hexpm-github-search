defmodule HexGh.Repo.Migrations.AddTsvectorAndHnswToKnowledge do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE knowledge
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(content, ''))) STORED;
    """)

    execute("CREATE INDEX IF NOT EXISTS knowledge_search_vector_idx ON knowledge USING GIN (search_vector);")
    execute("CREATE INDEX IF NOT EXISTS knowledge_embedding_hnsw_idx ON knowledge USING hnsw (embedding vector_cosine_ops);")
  end

  def down do
    execute("DROP INDEX IF EXISTS knowledge_embedding_hnsw_idx;")
    execute("DROP INDEX IF EXISTS knowledge_search_vector_idx;")

    execute("""
    ALTER TABLE knowledge
    DROP COLUMN IF EXISTS search_vector;
    """)
  end
end
