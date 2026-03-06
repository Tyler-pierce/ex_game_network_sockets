defmodule GameNetworkingSockets.ExSocketManager.SocketServer do
  use GenServer, restart: :transient

  alias GameNetworkingSockets.Global
  alias GameNetworkingSockets.ExSocketManager.Struct.SocketServerState, as: SSS
  alias GameNetworkingSockets.Socket

  @default_msgs_per_poll 2000

  def start_link([], opts) do
    GenServer.start_link(
      __MODULE__,
      to_state(opts),
      name: Keyword.fetch!(opts, :name)
    )
  end

  @doc """
  Create initial state struct of socket server
  """
  def to_state(opts) do
    %SSS{
      name: Keyword.fetch!(opts, :name),
      ip: Keyword.fetch!(opts, :ip),
      port: Keyword.fetch!(opts, :port),
      poll: Keyword.fetch!(opts, :poll)
    }
  end

  @impl true
  def init(%SSS{ip: ip, port: port, poll: poll} = state) do
    Global.init!()

    {:ok, server} = Socket.listen(ip, port)

    :timer.send_after(poll, :poll)

    {:ok, Map.put(state, :server, server)}
  end

  @impl true
  def handle_call(:peek, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:poll, state) do
    Global.poll_callbacks()
    
    state
    |> poll_connection()
    |> schedule_poll()
    |> noreply()
  end

  def handle_info(_, state), do: state

  # PRIVATE FUNCTIONS
  ###################
  defp poll_connection(%{server: %{poll_group: poll_group}, clients_connected: clients_connected} = state) do
    Global.poll_connection_status_changes()
    |> Enum.reduce(state, fn event, state ->
      case {event.old_state, event.new_state} do
        {0, 1} -> # New incoming connection — accept it
          Socket.accept(event.conn, poll_group)

          state

        {1, 3} -> # Connection accepted
          Map.put(state, :clients_connected, clients_connected + 1)

        {_, 4} -> # Closed by peer
          Socket.close_connection(event.conn)
          Map.put(state, :clients_connected, clients_connected - 1)

        {_, 5} -> # Problem detected locally
          Socket.close_connection(event.conn)
          Map.put(state, :clients_connected, clients_connected - 1)

        _ ->
          state
      end
    end)
    |> process_messages(Socket.receive_messages_on_poll_group(poll_group, @default_msgs_per_poll), 0)
  end

  defp process_messages(%{messages_received: received} = state, [], amt_processed) do
    Map.put(state, :messages_received, received + amt_processed)
  end

  defp process_messages(state, [_msg | t], amt_processed) do
    # Do something with message (TODO: state can have handler added)

    process_messages(state, t, amt_processed + 1)
  end
  
  defp noreply(state), do: {:noreply, state}

  defp schedule_poll(%{poll: poll} = state) do
    :timer.send_after(poll, :poll)

    state
  end
end
