defmodule StdioMcp.Tools.Remember do
  @moduledoc "Save a technical learning or pain point to the knowledge base."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias StdioMcp.Memory

  schema do
    field(:text, :string, required: true, description: "Detailed description of the lesson learned, bug fix, or pattern to store in the knowledge base.")
  end

  @impl true
  def execute(%{text: text}, frame) do
    Task.Supervisor.start_child(StdioMcp.TaskSupervisor, fn ->
      Memory.process_remember(text)
    end)

    {:reply,
     Response.text(Response.tool(), Jason.encode!(%{accepted: true, status: "processing"})),
     frame}
  end
end
