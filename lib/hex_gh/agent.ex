defmodule HexGh.Agent do
  @moduledoc false

  alias HexGh.AI.Mistral
  alias HexGh.MCPServer
  alias HexGh.Memory

  @system_prompt """
  You are a helpful research assistant specializing in Elixir/Erlang packages and GitHub projects.
  You MUST use one of the available tools to answer every query. Pick the most relevant tool.
  Respond in plain text. Use short paragraphs. No Markdown formatting, no emojis, no headers, no bullet lists.
  For package results, always include: name, description, latest version, last updated date, total downloads, recent downloads, and hex.pm link.
  For GitHub issues, always include: title, URL, state, and creation date.
  Include up to 5 most relevant results.
  """

  def process_query(user_prompt, opts \\ []) do
    user_id = Keyword.get(opts, :user_id, "default")

    with :ok <- check_rate_limit(user_id),
         {:ok, context} <- build_memory_context(user_prompt),
         {:ok, tool_call} <- intent_pass(user_prompt, context),
         {:ok, tool_result} <- dispatch_tool(tool_call) do
      synthesis_pass(user_prompt, tool_call, tool_result)
    else
      {:error, {:out_of_scope, message}} -> {:ok, message}
      error -> error
    end
  end

  def build_memory_context(prompt) do
    threshold = Application.get_env(:hex_gh, :memory_distance_threshold, 0.7)

    with {:ok, embedding} <- Mistral.embed(prompt),
         {:ok, results} when results != [] <- Memory.search_relevant(embedding, 3) do
      relevant = Enum.filter(results, fn %{distance: d} -> d < threshold end)

      if relevant == [] do
        {:ok, ""}
      else
        context = Enum.map_join(relevant, "\n", fn %{content: c} -> "- #{c}" end)
        {:ok, "<user_saved_knowledge>\n#{context}\n</user_saved_knowledge>"}
      end
    else
      _ -> {:ok, ""}
    end
  end

  defp intent_pass(user_prompt, context) do
    messages = [
      %{role: "system", content: @system_prompt <> "\n\n" <> context},
      %{role: "user", content: user_prompt}
    ]

    case Mistral.chat(messages, MCPServer.tool_schemas(), tool_choice: "any") do
      {:ok, %{"tool_calls" => [tool_call | _]}} ->
        {:ok, tool_call}

      {:ok, %{"content" => content}} ->
        {:error, {:no_tool_call, content}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp dispatch_tool(%{"function" => %{"name" => name, "arguments" => args}}) do
    case parse_tool_args(args) do
      {:ok, parsed_args} -> MCPServer.call_tool(name, parsed_args)
      {:error, _} = error -> error
    end
  end

  defp parse_tool_args(args) when is_map(args), do: {:ok, args}
  defp parse_tool_args(args) when is_binary(args), do: Jason.decode(args)
  defp parse_tool_args(_), do: {:error, :invalid_tool_args}

  defp synthesis_pass(user_prompt, tool_call, tool_result) do
    tool_name = get_in(tool_call, ["function", "name"])
    tool_call_id = tool_call["id"] || "call_1"

    messages = [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: user_prompt},
      %{
        role: "assistant",
        tool_calls: [tool_call]
      },
      %{
        role: "tool",
        tool_call_id: tool_call_id,
        name: tool_name,
        content: tool_result
      }
    ]

    case Mistral.chat(messages) do
      {:ok, %{"content" => content}} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_rate_limit(user_id) do
    case Hammer.check_rate("mistral:#{user_id}", 60_000, 20) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end
end
