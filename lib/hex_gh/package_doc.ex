defmodule HexGh.PackageDoc do
  use Ecto.Schema
  import Ecto.Changeset

  schema "package_docs" do
    field(:package, :string)
    field(:version, :string)
    field(:doc_type, :string)
    field(:module, :string)
    field(:function, :string)
    field(:signature, :string)
    field(:content, :string)
    field(:code_snippet, :string)
    field(:hexdocs_url, :string)
    field(:embedding, Pgvector.Ecto.Vector)

    timestamps()
  end

  @required ~w(package version doc_type content)a
  @optional ~w(module function signature code_snippet hexdocs_url embedding)a

  def changeset(package_doc \\ %__MODULE__{}, attrs) do
    package_doc
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
  end
end
