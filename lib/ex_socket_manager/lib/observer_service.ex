defmodule GameNetworkingSockets.ExSocketManager.ObserverService do
  @moduledoc """
  A global observer for tracking and monitoring existing servers and 
  clients
  """
  use GenServer

  alias GameNetworkingSockets.ExSocketManager.{SocketSupervisor, ClientSupervisor}

  alias GameNetworkingSockets.ExSocketManager.Struct.ServerObserverState, as: SOS
  alias GameNetworkingSockets.ExSocketManager.Struct.SocketServerState, as: SSS
  alias GameNetworkingSockets.ExSocketManager.Struct.SocketClientState, as: SCS

  @default_tick :timer.seconds(1)
  @server_fields [:server, :ip, :port]
  @client_fields [:name, :conn, :ip, :port]

  def start_link(opts) do
    case GenServer.start_link(
      __MODULE__,
      %SOS{},
      name: name(Keyword.get(opts, :name))
    ) do
      {:ok, _} = result -> result
      {:error, {:already_started, _pid}} -> :ignore
    end
  end

  @doc "process name of this server"
  def name(nil), do: {:via, :syn, {:observers, :global}}
  def name(name), do: {:via, :syn, {:observers, name}}

  @impl true
  def init(_) do
    :timer.send_after(@default_tick, :tick)

    {:ok, update_nodes(%SOS{})}
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

  @impl true
  def handle_info(:tick, state) do
    :timer.send_after(@default_tick, :tick)

    {:noreply, Map.put(state, :nodes, nodes())}
  end

  # PRIVATE FUNCTIONS
  ###################
  defp add_client(clients, pid, %SCS{} = client_state) do
     Map.put(clients, pid, Map.take(client_state, @client_fields))
  end

  defp add_client(clients, _, _), do: clients

  defp add_server(servers, pid, %SSS{} = server_state) do
     Map.put(servers, pid, Map.take(server_state, @server_fields))
  end

  defp add_server(servers, _, _), do: servers

  defp nodes, do: [node() | Node.list()]

  defp find_servers(%{nodes: nodes} = state) do
    clients =
      Enum.reduce(nodes, %{}, fn node, acc ->
        node
        |> :rpc.call(Process, :whereis, [SocketSupervisor])
        |> DynamicSupervisor.which_children()
        |> add_children(acc, @server_fields)
      end)

    Map.put(state, :clients, clients)
  end

  defp find_clients(%{nodes: nodes} = state) do
    servers = 
      Enum.reduce(nodes, %{}, fn node, acc ->
        node
        |> :rpc.call(Process, :whereis, [ClientSupervisor])
        |> DynamicSupervisor.which_children()
        |> add_children(acc, @client_fields)
      end)

    Map.put(state, :servers, servers)
  end

  defp add_children(children, acc, take_fields) do
    Enum.reduce(children, acc, fn %{child: child}, acc ->
       case child do
         child when is_pid(child) ->
           state = GenServer.call(child, :peek)

           Map.put(acc, child, Map.take(state, take_fields))

         _restarting ->
           acc
       end
     end)
  end

  defp update_nodes(%{nodes: nodes} = state) do
    nodes_now = nodes()
    cond do
      length(nodes_now) < length(nodes) ->
        # Node down event.
        state
        |> Map.put(:nodes, nodes_now)
        |> find_servers()
        |> find_clients()

      length(nodes_now) > length(nodes) ->
        # Node added event!
        Map.put(state, :nodes, nodes_now)

      true ->
        # No changes
        state
    end
  end
end
