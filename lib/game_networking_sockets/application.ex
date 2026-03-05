defmodule GameNetworkingSockets.Application do
  @moduledoc false

  use Application

  alias GameNetworkingSockets.ExSocketManager.SocketSupervisor

  @impl true
  def start(_type, _args) do
    # Setup Caching Cluster (if application clustered)
    :ok = setup_cache_cluster()

    # Add scopes that will be in the cluster process dictionary
    :syn.add_node_to_scopes([
      :socket_servers
    ])

    children = [
      {SocketSupervisor, name: GameNetworkingSockets.ExSocketManager.SocketSupervisor}
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
end
