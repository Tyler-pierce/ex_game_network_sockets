defmodule GameNetworkingSockets.Application do
  @moduledoc false

  use Application

  alias GameNetworkingSockets.ExSocketManager.{ObserverService, SocketSupervisor, ClientSupervisor}

  @impl true
  def start(_type, _args) do
    # Setup Caching Cluster (if application clustered)
    :ok = setup_cache_cluster()

    # Add scopes that will be in the cluster process dictionary
    :syn.add_node_to_scopes([
      :observers
    ])

    children = [
      {Cluster.Supervisor, [cluster_topology(), [name: GameNetworkingSockets.ClusterSupervisor]]},
      {SocketSupervisor, name: GameNetworkingSockets.ExSocketManager.SocketSupervisor},
      {ClientSupervisor, name: GameNetworkingSockets.ExSocketManager.ClientSupervisor},
      {ObserverService, []}
    ]

    opts = [strategy: :one_for_one, name: GameNetworkingSockets.Supervisor]

    Supervisor.start_link(children, opts)
  end

  # PRIVATE FUNCTIONS
  ###################
  defp setup_cache_cluster() do
    [node()|Node.list()]
    |> Enum.each(&:net_adm.ping/1)
  end

  defp cluster_topology() do
    [
      default: [
        strategy: Cluster.Strategy.Epmd,
        config: [hosts: [:"a@127.0.0.1", :"b@127.0.0.1", :"c@127.0.0.1", :"d@127.0.0.1"]],
      ]
    ]
  end
end
