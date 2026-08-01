defmodule StdioMcp.AI.Mistral do
  @moduledoc "Mistral API client for embeddings and chat decisions."

  def small_model do
    Application.get_env(:stdio_mcp, :mistral_model_small) ||
      Application.get_env(:stdio_mcp, :mistral_chat_model, "mistral-small-latest")
  end

  def large_model do
    Application.get_env(:stdio_mcp, :mistral_model_large) ||
      Application.get_env(:stdio_mcp, :mistral_chat_model_large, "mistral-medium-latest")
  end

  def embed_model do
    Application.get_env(:stdio_mcp, :mistral_model_embed) ||
      Application.get_env(:stdio_mcp, :mistral_embed_model, "mistral-embed")
  end

  def api_key do
    System.get_env("MISTRAL_API_KEY") || Application.get_env(:stdio_mcp, :mistral_api_key)
  end

  def embed(text) when is_binary(text) do
    case embed_batch([text]) do
      {:ok, [vector]} -> {:ok, vector}
      {:error, reason} -> {:error, reason}
    end
  end

  def embed_batch(texts) when is_list(texts) do
    api_key = api_key()

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      url = "#{Application.get_env(:stdio_mcp, :mistral_api_url)}/embeddings"
      embed_model = Application.get_env(:stdio_mcp, :mistral_embed_model)

      headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      body = %{model: embed_model, input: texts}

      case Req.post(url, json: body, headers: headers, finch: [name: StdioMcp.Finch]) do
        {:ok, %{status: 200, body: %{"data" => data}}} ->
          vectors = Enum.map(data, & &1["embedding"])
          {:ok, vectors}

        {:ok, %{status: 429}} ->
          {:error, {429, "Rate limit exceeded"}}

        {:ok, %{status: status, body: err}} ->
          {:error, {status, err}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def chat(messages, _tools \\ [], opts \\ []) do
    api_key = api_key()

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      url = "#{Application.get_env(:stdio_mcp, :mistral_api_url)}/chat/completions"
      model = Keyword.get(opts, :model, Application.get_env(:stdio_mcp, :mistral_chat_model))

      headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      body = %{model: model, messages: messages, temperature: 0.2}

      case Req.post(url, json: body, headers: headers, finch: [name: StdioMcp.Finch]) do
        {:ok, %{status: 200, body: %{"choices" => [%{"message" => msg} | _]}}} ->
          {:ok, msg}

        {:ok, %{status: status, body: err}} ->
          {:error, {status, err}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
