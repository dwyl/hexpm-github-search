defmodule HexGh.Docs.Poller do
  @moduledoc """
  GenServer that periodically polls Hex.pm for newly updated packages
  and triggers background ingestion via `HexGh.Docs.IngestionWorker`.
  """

  use GenServer
  require Logger

  alias HexGh.Docs.IngestionWorker

  @default_interval :timer.minutes(30)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Triggers an immediate poll out-of-band.
  """
  def poll_now(pid_or_name \\ __MODULE__) do
    GenServer.cast(pid_or_name, :poll_now)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    enabled? = Keyword.get(opts, :enabled, true)

    if enabled? do
      schedule_next_poll(100)
    end

    {:ok, %{interval: interval, enabled?: enabled?}}
  end

  @impl true
  def handle_cast(:poll_now, state) do
    do_poll()
    {:noreply, state}
  end

  @impl true
  def handle_info(:poll, state) do
    do_poll()
    schedule_next_poll(state.interval)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_next_poll(delay) do
    Process.send_after(self(), :poll, delay)
  end

  defp do_poll do
    url = "https://hex.pm/api/packages?sort=updated_at&page=1"

    case Req.get(url, headers: [{"user-agent", "hex_gh/1.0"}]) do
      {:ok, %{status: 200, body: packages}} when is_list(packages) ->
        Logger.info("[Docs.Poller] Polled #{length(packages)} packages from Hex.pm")

        packages
        |> Enum.take(5)
        |> Enum.each(&ingest_package/1)

      {:ok, %{status: status}} ->
        Logger.warning("[Docs.Poller] Hex.pm API returned status #{status}")

      {:error, reason} ->
        Logger.error("[Docs.Poller] Failed to fetch Hex.pm packages: #{inspect(reason)}")
    end
  end

  defp ingest_package(pkg) do
    package_name = Map.get(pkg, "name")
    latest_version = Map.get(pkg, "latest_stable_version") || Map.get(pkg, "latest_version")

    if package_name do
      Task.Supervisor.start_child(HexGh.TaskSupervisor, fn ->
        IngestionWorker.ingest(package_name, latest_version || "latest")
      end)
    end
  end
end
