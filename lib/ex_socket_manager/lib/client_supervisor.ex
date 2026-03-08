defmodule GameNetworkingSockets.ExSocketManager.ClientSupervisor do
  use DynamicSupervisor

  alias GameNetworkingSockets.ExSocketManager.ClientServer

  def start_link([{:name, name}]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: name)
  end

  def start_child(opts) do
    DynamicSupervisor.start_child(__MODULE__, {ClientServer, opts})
  end

  @impl true
  def init(opts) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [opts]
    )
  end

  def children(), do: DynamicSupervisor.which_children(__MODULE__)
end
