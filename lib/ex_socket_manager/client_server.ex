defmodule GameNetworkingSockets.ExSocketManager.ClientServer do
  use GenServer, restart: :transient

  alias GameNetworkingSockets.Global
  alias GameNetworkingSockets.ExSocketManager.Struct.SocketClientState, as: SCS
  alias GameNetworkingSockets.Socket

  # Idle time until genserver eliminates itself
  @default_server_ttl :timer.hours(1)

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
  def name(%SCS{name: name}), do: name(name)

  def name(name) do
    {:via, :syn, {:client_servers, name}}
  end

  @doc """
  Create initial state struct of socket server
  """
  def to_state(opts) do
    %SCS{
      name: Keyword.fetch!(opts, :name),
      ip: Keyword.fetch!(opts, :ip),
      port: Keyword.fetch!(opts, :port),
      poll: Keyword.fetch!(opts, :poll),
      timeout: Keyword.get(opts, :timeout, @default_server_ttl)
    }
  end

  @impl true
  def init(%SCS{timeout: timeout, ip: ip, port: port, poll: poll} = state) do
    :timer.send_after(timeout, :server_timeout)

    Global.init!()

    {:ok, conn} = GameNetworkingSockets.Socket.connect(ip, port)

    # TODO: send message handle async
    #{:ok, msg_num} = Socket.send(client_conn, "hello from elixir!", Socket.send_reliable())

    :timer.send_after(poll, :poll)

    {:ok, Map.put(state, :conn, conn)}
  end

  @impl true
  def handle_call(:peek, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:net_stats, _from, state) do
    # TODO
    {:reply, state, state}
  end

  @impl true
  def handle_info(:poll, %{poll: poll, server: server} = state) do
    Global.poll_callbacks()

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
