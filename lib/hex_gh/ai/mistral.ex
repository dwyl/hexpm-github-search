defmodule HexGh.AI.Mistral do
  @moduledoc """
  Mistral AI API client for chat completions and embeddings.

  Uses the `/chat/completions` endpoint for both plain chat and tool-calling.
  This is the only Mistral endpoint that supports function/tool calling, which
  is how the agent pipeline invokes MCP tools (search_hex_packages,
  search_github_issues, save_memory) via `tool_choice: "any"`.
  """

  defp base_url, do: Application.get_env(:hex_gh, :mistral_api_url, "https://api.mistral.ai/v1")
  defp chat_model, do: Application.get_env(:hex_gh, :mistral_chat_model, "mistral-small-latest")
  defp embed_model, do: Application.get_env(:hex_gh, :mistral_embed_model, "mistral-embed")

  defp api_key do
    Application.get_env(:hex_gh, :mistral_api_key) ||
      raise "MISTRAL_API_KEY not configured"
  end

  @spec chat(any()) ::
          {:error,
           {non_neg_integer(), any()}
           | %{:__exception__ => any(), :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  def chat(messages, tools \\ [], opts \\ []) do
    body =
      %{model: Keyword.get(opts, :model, chat_model()), messages: messages}
      |> maybe_add_tools(tools, opts)

    post("/chat/completions", body)
    |> handle_chat_response()
  end

  @spec embed(binary()) ::
          {:error,
           {non_neg_integer(), any()}
           | %{:__exception__ => any(), :__struct__ => atom(), optional(atom()) => any()}}
          | {:ok, any()}
  def embed(text) when is_binary(text) do
    body = %{model: embed_model(), input: [text]}

    case post("/embeddings", body) do
      {:ok, %{"data" => [%{"embedding" => embedding} | _]}} ->
        {:ok, embedding}

      {:error, _} = error ->
        error
    end
  end

  # defp maybe_add_tools(body, [], _opts), do: body # useless??

  defp maybe_add_tools(body, tools, opts) do
    body
    |> Map.put(:tools, tools)
    |> Map.put(:tool_choice, Keyword.get(opts, :tool_choice, "auto"))
  end

  defp handle_chat_response({:ok, %{"choices" => [%{"message" => message} | _]}}) do
    {:ok, message}
  end

  defp handle_chat_response({:error, _} = error), do: error

  defp post(path, body) do
    case Req.post("#{base_url()}#{path}",
           json: body,
           headers: [{"authorization", "Bearer #{api_key()}"}],
           finch: HexGh.Finch
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
