defmodule GameNetworkingSockets.ExSocketManager.ObserverService do
  @moduledoc """
  A global observer for tracking and monitoring existing servers and 
  clients
  """
  use GenServer

  alias GameNetworkingSockets.ExSocketManager.Struct.ServerObserverState, as: SOS
  alias GameNetworkingSockets.ExSocketManager.Struct.SocketServerState, as: SSS
  alias GameNetworkingSockets.ExSocketManager.Struct.SocketClientState, as: SCS

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      %SOS{},
      name: name(Keyword.get(opts, :name))
    )
  end

  @doc "process name of this server"
  def name(nil), do: {:via, :syn, {:observers, :global}}
  def name(name), do: {:via, :syn, {:observers, name}}

  @impl true
  def init(_) do
    {:ok, %SOS{nodes: nodes()}}
  end

  @impl true
  def handle_call(:peek, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:client_added, pid}, %{clients: clients} = state) do
    case GenServer.call(pid, :peek) do
      %{} = client_state ->
        {:noreply, Map.put(state, :clients, add_client(clients, pid, client_state))}
      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:server_added, pid}, %{servers: servers} = state) do
    case GenServer.call(pid, :peek) do
      %{} = server_state ->
        {:noreply, Map.put(state, :servers, add_server(servers, pid, server_state))}
      _ ->
        {:noreply, state}
    end
  end

  # PRIVATE FUNCTIONS
  ###################
  defp add_client(clients, pid, %SCS{} = client_state) do
     Map.put(clients, pid, Map.take(client_state, [:name, :conn, :ip, :port]))
  end

  defp add_client(clients, _, _), do: clients

  defp add_server(servers, pid, %SSS{} = server_state) do
     Map.put(servers, pid, Map.take(server_state, [:server, :ip, :port]))
  end

  defp add_server(servers, _, _), do: servers

  defp nodes, do: [node() | Node.list()]
end
