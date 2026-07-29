defmodule HexGh.Knowledge do
  use Ecto.Schema
  import Ecto.Changeset

  schema "knowledge" do
    field(:kind, :string)
    field(:title, :string)
    field(:content, :string)
    field(:metadata, :map, default: %{})
    field(:embedding, Pgvector.Ecto.Vector)

    timestamps()
  end

  @required ~w(kind title content embedding)a
  @optional ~w(metadata)a

  def changeset(knowledge \\ %__MODULE__{}, attrs) do
    knowledge
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:kind, ~w(learning pain_point decision pattern package_note))
  end
end
