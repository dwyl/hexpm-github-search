defmodule HexGhWeb.ChatLive do
  use HexGhWeb, :live_view

  alias HexGh.Agent.Pipeline

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream(:messages, [])
     |> assign(:input, "")
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("send", %{"input" => input}, socket) when input != "" do
    user_msg = %{id: System.unique_integer([:positive]), role: :user, content: input}

    socket =
      socket
      |> stream_insert(:messages, user_msg)
      |> assign(:input, "")
      |> assign(:loading, true)

    send(self(), {:run_pipeline, input})
    {:noreply, socket}
  end

  def handle_event("send", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("update_input", %{"input" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  @impl true
  def handle_info({:run_pipeline, text}, socket) do
    require Logger

    content =
      case Pipeline.run(%{text: text, is_audio: false}) do
        {:ok, response} ->
          response

        {:error, :rate_limited} ->
          "Rate limit exceeded. Please wait a moment."

        {:error, {:no_tool_call, response}} ->
          response

        {:error, reason} ->
          Logger.error("Pipeline failed: #{inspect(reason)}")
          "Something went wrong. Please try again."
      end

    assistant_msg = %{id: System.unique_integer([:positive]), role: :assistant, content: content}

    socket =
      socket
      |> stream_insert(:messages, assistant_msg)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex flex-col h-[calc(100vh-12rem)]">
        <h1 class="text-2xl font-bold mb-4">HexGh Assistant</h1>

        <div id="messages" phx-update="stream" class="flex-1 overflow-y-auto space-y-4 mb-4">
          <div :for={{dom_id, msg} <- @streams.messages} id={dom_id} class="flex flex-col">
            <div class={[
              "rounded-lg px-4 py-2 max-w-[80%] whitespace-pre-wrap",
              msg.role == :user && "self-end bg-primary text-primary-content",
              msg.role == :assistant && "self-start bg-base-200"
            ]}>
              {msg.content}
            </div>
          </div>
        </div>

        <div :if={@loading} class="flex items-center gap-2 text-base-content/60 mb-2">
          <span class="loading loading-dots loading-sm"></span> Thinking...
        </div>

        <form id="chat-form" phx-submit="send" phx-change="update_input" class="flex gap-2">
          <input
            type="text"
            name="input"
            value={@input}
            placeholder="Ask about Elixir packages or GitHub issues..."
            class="input input-bordered flex-1"
            autocomplete="off"
            disabled={@loading}
          />
          <button type="submit" class="btn btn-primary" disabled={@loading || @input == ""}>
            Send
          </button>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
