defmodule HexGh.Knowledge do
  use Ecto.Schema
  import Ecto.Changeset

  alias HexGh.Knowledge.Vocabulary

  schema "knowledge" do
    field(:kind, :string)
    field(:title, :string)
    field(:content, :string)
    field(:metadata, :map, default: %{})
    field(:embedding, Pgvector.Ecto.Vector)
    field(:outdated, :boolean, default: false)

    timestamps()
  end

  @required ~w(kind title content embedding)a
  @optional ~w(metadata outdated)a

  def changeset(knowledge \\ %__MODULE__{}, attrs) do
    knowledge
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    # `cast/3` already rejects a non-string `kind` (the structuring model has
    # returned it as a JSON object), so only the vocabulary needs checking here.
    |> validate_inclusion(:kind, Vocabulary.kinds(),
      message: "must be one of: #{Enum.join(Vocabulary.kinds(), ", ")}"
    )
    |> update_change(:metadata, &clean_metadata/1)
  end

  # `domain` is no longer part of the taxonomy: it collapsed into a single
  # value, correlated with `kind`, and duplicated what `stack` and `package`
  # already record as extracted facts rather than judgments.
  defp clean_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.drop([:domain, "domain"])
    |> normalize_stack()
  end

  defp clean_metadata(metadata), do: metadata

  defp normalize_stack(metadata) do
    case fetch_stack(metadata) do
      :error ->
        metadata

      {:ok, key, tags} ->
        Map.put(metadata, key, Vocabulary.normalize_tags(tags))
    end
  end

  defp fetch_stack(metadata) do
    cond do
      is_list(metadata[:stack]) -> {:ok, :stack, metadata[:stack]}
      is_list(metadata["stack"]) -> {:ok, "stack", metadata["stack"]}
      true -> :error
    end
  end
end
