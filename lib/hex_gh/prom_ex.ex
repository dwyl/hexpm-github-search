defmodule HexGh.PromEx do
  @moduledoc "PromEx metrics configuration for BEAM, Phoenix, Ecto, and AI metrics."
  use PromEx, otp_app: :hex_gh

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: HexGhWeb.Router, endpoint: HexGhWeb.Endpoint},
      Plugins.Ecto,
      HexGh.PromEx.AIPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus_hexgh",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "ecto.json"}
    ]
  end
end
