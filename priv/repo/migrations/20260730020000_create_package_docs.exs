defmodule HexGh.Repo.Migrations.CreatePackageDocs do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    create table(:package_docs) do
      add(:package, :string, null: false)
      add(:version, :string, null: false)
      add(:doc_type, :string, null: false)
      add(:module, :string)
      add(:function, :string)
      add(:signature, :text)
      add(:content, :text, null: false)
      add(:code_snippet, :text)
      add(:hexdocs_url, :text)
      add(:embedding, :vector, size: 1024)

      timestamps()
    end

    create(index(:package_docs, [:package, :version]))

    execute("""
    ALTER TABLE package_docs
    ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(module, '') || ' ' || coalesce(function, '') || ' ' || coalesce(content, ''))) STORED;
    """)

    execute("CREATE INDEX IF NOT EXISTS package_docs_search_vector_idx ON package_docs USING GIN (search_vector);")
    execute("CREATE INDEX IF NOT EXISTS package_docs_embedding_hnsw_idx ON package_docs USING hnsw (embedding vector_cosine_ops);")
  end

  def down do
    drop(table(:package_docs))
  end
end
