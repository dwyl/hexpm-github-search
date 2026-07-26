defmodule HexGh.Tools.Hex do
  @moduledoc false

  defp base_url, do: Application.get_env(:hex_gh, :hex_api_url, "https://hex.pm/api")

  def search_packages(query) do
    case Req.get("#{base_url()}/packages",
           params: [search: query],
           finch: HexGh.Finch
         ) do
      {:ok, %{status: 200, body: items}} when is_list(items) ->
        results =
          items
          |> Enum.take(5)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["name"],
              description: pkg["meta"]["description"],
              latest_version: get_in(pkg, ["releases", Access.at(0), "version"]),
              updated_at: pkg["updated_at"],
              downloads_total: get_in(pkg, ["downloads", "all"]) || 0,
              url: pkg["html_url"] || "https://hex.pm/packages/#{pkg["name"]}"
            }
          end)

        {:ok, Jason.encode!(results)}

      {:ok, %{status: status, body: body}} ->
        {:error, "Hex.pm API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Hex.pm request failed: #{inspect(reason)}"}
    end
  end

  def get_package(name) do
    case Req.get("#{base_url()}/packages/#{name}", finch: HexGh.Finch) do
      {:ok, %{status: 200, body: pkg}} ->
        {:ok, pkg}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
