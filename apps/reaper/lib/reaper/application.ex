defmodule Reaper.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children =
      [
        libcluster(),
        {Horde.Registry, [name: Reaper.Registry]},
        {Horde.Supervisor, [name: Reaper.Horde.Supervisor, strategy: :one_for_one]},
        {HordeConnector, [supervisor: Reaper.Horde.Supervisor, registry: Reaper.Registry]},
        Reaper.ConfigServer,
        redis(),
        dataset_subscriber()
      ]
      |> List.flatten()

    opts = [strategy: :one_for_one, name: Reaper.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dataset_subscriber() do
    case Application.get_env(:smart_city_registry, :redis) do
      nil -> []
      _ -> {SmartCity.Registry.Subscriber, [message_handler: Reaper.MessageHandler]}
    end
  end

  defp redis do
    Application.get_env(:redix, :host)
    |> case do
      nil -> []
      host -> {Redix, host: host, name: :redix}
    end
  end

  defp libcluster do
    case Application.get_env(:libcluster, :topologies) do
      nil -> []
      topology -> {Cluster.Supervisor, [topology, [name: Cluster.ClusterSupervisor]]}
    end
  end
end
