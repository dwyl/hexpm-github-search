defmodule HexGh.Knowledge.VocabularyTest do
  use ExUnit.Case, async: true

  alias HexGh.Knowledge
  alias HexGh.Knowledge.Vocabulary

  @embedding List.duplicate(0.1, 1024)

  defp changeset(attrs) do
    Knowledge.changeset(Map.merge(%{title: "t", content: "c", embedding: @embedding}, attrs))
  end

  describe "kinds" do
    test "every kind the changeset accepts is one the vocabulary advertises" do
      # The original defect: `recall` advertised filter values that the writer
      # never emitted, so every filtered search returned nothing. Both sides now
      # derive from `kinds/0`; this fails if either is hardcoded again.
      for kind <- Vocabulary.kinds() do
        assert changeset(%{kind: kind}).valid?, "changeset rejected advertised kind #{kind}"
        assert Vocabulary.kinds_for_schema() =~ kind
        assert Vocabulary.kinds_for_schema_description() =~ kind
      end
    end

    test "has no generic catch-all" do
      # A generic bucket collapses the taxonomy: every entry qualifies, the
      # model always picks it, and the filter stops discriminating. All five
      # rows of the previous SQLite base were `learning`.
      refute "learning" in Vocabulary.kinds()

      refute changeset(%{kind: "learning"}).valid?
    end

    test "rejects a kind outside the vocabulary" do
      changeset = changeset(%{kind: "quirk"})

      refute changeset.valid?
      assert {"must be one of: " <> _, _} = changeset.errors[:kind]
    end

    test "rejects a non-scalar kind" do
      refute changeset(%{kind: %{"learning" => true}}).valid?
    end
  end

  describe "infer_kind/1" do
    test "derives the kind from the fields present rather than a constant" do
      assert Vocabulary.infer_kind(%{"symptom" => "boom"}) == "pain_point"
      assert Vocabulary.infer_kind(%{"cause" => "race"}) == "pain_point"

      assert Vocabulary.infer_kind(%{"package" => "req", "package_version" => "~> 0.5"}) ==
               "package_note"

      assert Vocabulary.infer_kind(%{}) == "pattern"
    end

    test "never infers a kind outside the vocabulary" do
      for meta <- [%{}, %{"symptom" => "x"}, %{"package" => "p", "package_version" => "1"}] do
        assert Vocabulary.infer_kind(meta) in Vocabulary.kinds()
      end
    end
  end

  describe "stack tags" do
    test "normalizes so equivalent tags collapse to one" do
      # "claude code" and "claude-code" were both stored for the same
      # technology, which silently broke the exact-match stack filter.
      assert Vocabulary.normalize_tags(["Claude Code", "claude-code"]) == ["claude_code"]
      assert Vocabulary.normalize_tags(["  Elixir ", "PostGres"]) == ["elixir", "postgres"]
    end

    test "drops non-strings and blanks" do
      assert Vocabulary.normalize_tags(["ok", 42, "", nil]) == ["ok"]
      assert Vocabulary.normalize_tags(nil) == []
    end

    test "changeset normalizes stack and strips domain" do
      changeset =
        changeset(%{kind: "pattern", metadata: %{"domain" => "code", "stack" => ["Claude Code"]}})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :metadata) == %{"stack" => ["claude_code"]}
    end
  end
end
