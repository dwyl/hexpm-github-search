defmodule HexGh.Tools.SaveMemory do
  @moduledoc false

  alias HexGh.AI.Mistral
  alias HexGh.Memory
  alias HexGh.Tools.Hex

  def save(fact, nil) do
    save_with_embedding("general", fact)
  end

  def save(fact, package) when is_binary(package) do
    case Hex.get_package(package) do
      {:ok, pkg} ->
        enriched =
          """
          #{fact}

          [Package: #{pkg["name"]} v#{get_in(pkg, ["releases", Access.at(0), "version"])}]
          Description: #{get_in(pkg, ["meta", "description"])}
          Downloads: #{get_in(pkg, ["downloads", "all"]) || "N/A"}
          Links: #{pkg["meta"]["links"] |> inspect()}
          """
          |> String.trim()

        save_with_embedding("package", enriched)

      {:error, :not_found} ->
        save_with_embedding("package", "#{fact} [Package '#{package}' not found on Hex.pm]")

      {:error, _reason} ->
        save_with_embedding("general", fact)
    end
  end

  defp save_with_embedding(category, content) do
    with {:ok, embedding} <- Mistral.embed(content),
         {:ok, id} <- Memory.save_fact(category, content, embedding) do
      {:ok, "Saved to memory (id: #{id})"}
    else
      {:error, reason} -> {:error, "Failed: #{inspect(reason)}"}
    end
  end
end
