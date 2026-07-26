defmodule HexGh.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HexGh.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Register Telegram webhook after supervision tree is up (Finch must be running)
    if webhook_url = Application.get_env(:hex_gh, :telegram_webhook_url) do
      HexGh.Telegram.register_webhook(webhook_url)
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HexGhWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
