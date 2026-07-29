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
    configure_boruta()

    children =
      [
        HexGh.PromEx,
        HexGh.Repo,
        HexGhWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:hex_gh, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: HexGh.PubSub},
        {Finch, name: HexGh.Finch, pools: %{"https://api.mistral.ai" => [size: 10]}},
        {Task.Supervisor, name: HexGh.TaskSupervisor},
        HexGh.Memory,
        {HexGh.MCP.Server, transport: {:streamable_http, start: true}},
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

  defp configure_boruta do
    boruta_config = Application.get_env(:boruta, Boruta.Oauth, [])
    boruta_config = Keyword.put_new(boruta_config, :repo, HexGh.Repo)
    boruta_contexts = Keyword.get(boruta_config, :contexts, [])

    boruta_contexts =
      Keyword.put_new(boruta_contexts, :resource_owners, HexGh.OAuth.ResourceOwners)

    boruta_config = Keyword.put(boruta_config, :contexts, boruta_contexts)

    one_year = 60 * 60 * 24 * 365
    existing_max_ttl = Keyword.get(boruta_config, :max_ttl, [])

    max_ttl =
      existing_max_ttl
      |> Keyword.put_new(:access_token, one_year)
      |> Keyword.put_new(:refresh_token, one_year)

    boruta_config = Keyword.put(boruta_config, :max_ttl, max_ttl)
    Application.put_env(:boruta, Boruta.Oauth, boruta_config)
  end

  defp attach_mcp_telemetry do
    :telemetry.attach(
      "mcp-http-request",
      [:ex_mcp, :server, :http, :request],
      &__MODULE__.handle_mcp_event/4,
      nil
    )

    :telemetry.attach(
      "mcp-http-response",
      [:ex_mcp, :server, :http, :response],
      &__MODULE__.handle_mcp_event/4,
      nil
    )
  end

  def handle_mcp_event([:ex_mcp, :server, :http, :request], _measurements, metadata, _config) do
    Logger.info("MCP HTTP #{metadata[:method]} #{metadata[:path]}")
  end

  def handle_mcp_event([:ex_mcp, :server, :http, :response], _measurements, metadata, _config) do
    Logger.info("MCP HTTP response status=#{metadata[:status]}")
  end

  @impl true
  def config_change(changed, _new, removed) do
    HexGhWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
