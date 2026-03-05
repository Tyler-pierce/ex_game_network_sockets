defmodule GameNetworkingSockets.ExSocketManager.SocketServer do
  use GenServer, restart: :transient

  alias GameNetworkingSockets.Global
  alias GameNetworkingSockets.ExSocketManager.Struct.SocketServerState, as: SSS
  alias GameNetworkingSockets.Socket

  # Idle time until genserver eliminates itself
  @default_server_ttl :timer.hours(2)

  def start_link([], opts) do
    GenServer.start_link(
      __MODULE__,
      to_state(opts),
      name: name(Keyword.fetch!(opts, :name))
    )
  end

  @doc """
  Fetch process dictionary name of server
  """
  def name(%SSS{name: name}), do: name(name)

  def name(name) do
    {:via, :syn, {:socket_servers, name}}
  end

  @doc """
  Create initial state struct of socket server
  """
  def to_state(opts) do
    %SSS{
      name: Keyword.fetch!(opts, :name),
      ip: Keyword.fetch!(opts, :ip),
      port: Keyword.fetch!(opts, :port),
      poll: Keyword.fetch!(opts, :poll),
      timeout: Keyword.get(opts, :timeout, @default_server_ttl)
    }
  end

  @impl true
  def init(%SSS{timeout: timeout, ip: ip, port: port, poll: poll} = state) do
    :timer.send_after(timeout, :server_timeout)

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
  def handle_info(:poll, %{poll: poll, server: server} = state) do
    Global.poll_callbacks()

    for event <- Global.poll_connection_status_changes() do
      case {event.old_state, event.new_state} do
        {0, 1} ->
          # New incoming connection — accept it
          Socket.accept(event.conn, server.poll_group)

        {1, 3} ->
          # Connection fully established
          IO.puts("Client #{event.conn} connected")

        {_, 4} ->
          # Closed by peer
          IO.puts("Closed by peer")
          Socket.close_connection(event.conn)

        {_, 5} ->
          # Problem detected locally
          IO.puts("Problem detected locally")
          Socket.close_connection(event.conn)

        _ ->
          :ok
      end
    end

    messages = Socket.receive_messages_on_poll_group(server.poll_group)

    if length(messages) > 0 do
      IO.puts("Server received #{length(messages)} message(s)")

      for msg <- messages do
        IO.puts("payload: #{inspect(msg.payload)}")
      end
    end

    :timer.send_after(poll, :poll)

    {:noreply, state}
  end

  def handle_info(:server_timeout, state) do
    Global.kill()
    
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: state

  # PRIVATE FUNCTIONS
  ###################
end
