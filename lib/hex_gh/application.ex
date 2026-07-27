defmodule HexGh.Application do
  @moduledoc """
  - Uses Finch pool. Finch maintains persistent connection pools so you don't open a new
  TCP+TLS connection for every API call to Mistral, Hex.pm, GitHub, or Telegram.
  - the Telegram webhook is registered.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    attach_mcp_telemetry()

    children =
      [
        HexGhWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:hex_gh, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: HexGh.PubSub},
        {Finch, name: HexGh.Finch, pools: %{"https://api.mistral.ai" => [size: 10]}},
        {Task.Supervisor, name: HexGh.TaskSupervisor},
        HexGh.Memory,
        HexGhWeb.Endpoint
      ]

    opts = [strategy: :one_for_one, name: HexGh.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Register Telegram webhook after supervision tree is up (Finch must be running)
    if webhook_url = Application.get_env(:hex_gh, :telegram_webhook_url) do
      HexGh.Telegram.register_webhook(webhook_url)
    end

    result
  end

  defp attach_mcp_telemetry do
    :telemetry.attach(
      "mcp-http-request",
      [:ex_mcp, :server, :http, :request],
      fn _event, _measurements, metadata, _config ->
        Logger.info("MCP HTTP #{metadata[:method]} #{metadata[:path]}")
      end,
      nil
    )

    :telemetry.attach(
      "mcp-http-response",
      [:ex_mcp, :server, :http, :response],
      fn _event, _measurements, metadata, _config ->
        Logger.info("MCP HTTP response status=#{metadata[:status]}")
      end,
      nil
    )
  end

  @impl true
  def config_change(changed, _new, removed) do
    HexGhWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
