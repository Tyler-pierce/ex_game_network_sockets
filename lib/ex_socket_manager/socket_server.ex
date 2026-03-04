defmodule GameNetworkSockets.ExSocketManager.SocketServer do
  use GenServer, restart: :temporary

  alias GameNetworkingSockets.Global
  alias GameNetworkSockets.ExSocketManager.Struct.SocketServerState, as: SSS

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
  def init(%SSS{timeout: timeout} = state) do
    :timer.send_after(timeout, :server_timeout)

    Global.init!()

    {:ok, state}
  end

  @impl true
  def handle_call(:peek, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:server_timeout, state) do
    Global.kill()
    
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: state

  # PRIVATE FUNCTIONS
  ###################
end
