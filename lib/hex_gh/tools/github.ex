defmodule HexGh.Tools.GitHub do
  @moduledoc false

  defp base_url, do: Application.get_env(:hex_gh, :github_api_url, "https://api.github.com")

  def search_issues(org, query) do
    case Req.get("#{base_url()}/search/issues",
           params: [q: "org:#{org} #{query}"],
           headers: auth_headers(),
           finch: HexGh.Finch
         ) do
      {:ok, %{status: 200, body: %{"items" => items}}} ->
        results =
          items
          |> Enum.take(5)
          |> Enum.map(fn item ->
            %{
              repo: item["repository_url"] |> String.split("/") |> List.last(),
              number: item["number"],
              title: item["title"],
              state: item["state"],
              html_url: item["html_url"],
              snippet: String.slice(item["body"] || "", 0, 200)
            }
          end)

        {:ok, Jason.encode!(results)}

      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "GitHub request failed: #{inspect(reason)}"}
    end
  end

  defp auth_headers do
    case Application.get_env(:hex_gh, :github_token) do
      nil -> []
      token -> [{"authorization", "Bearer #{token}"}]
    end
  end
end
