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

  defp maybe_add_tools(body, [], _opts), do: body

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
           finch: [name: HexGh.Finch]
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        emit_telemetry(path, body, resp_body)
        {:ok, resp_body}

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp emit_telemetry(path, req_body, resp_body) do
    usage = Map.get(resp_body, "usage") || %{}

    model =
      Map.get(resp_body, "model") || Map.get(req_body, :model) || Map.get(req_body, "model") ||
        "unknown"

    measurements = %{
      prompt_tokens: Map.get(usage, "prompt_tokens", 0),
      completion_tokens: Map.get(usage, "completion_tokens", 0),
      total_tokens: Map.get(usage, "total_tokens", 0)
    }

    metadata = %{
      model: model,
      path: path
    }

    :telemetry.execute([:hex_gh, :ai, :mistral, :request], measurements, metadata)
  end
end
