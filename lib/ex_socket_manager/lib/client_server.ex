defmodule GameNetworkingSockets.ExSocketManager.ClientServer do
  use GenServer, restart: :transient

  alias GameNetworkingSockets.Global
  alias GameNetworkingSockets.ExSocketManager.Struct.SocketClientState, as: SCS
  alias GameNetworkingSockets.{Connection, Socket}

  def start_link([], opts) do
    GenServer.start_link(
      __MODULE__,
      to_state(opts),
      name: Keyword.fetch!(opts, :name)
    )
  end

  @doc """
  Create initial state struct of socket server.
  """
  def to_state(opts) do
    %SCS{
      name: Keyword.fetch!(opts, :name),
      ip: Keyword.fetch!(opts, :ip),
      port: Keyword.fetch!(opts, :port),
      poll: Keyword.fetch!(opts, :poll),
      lanes: Keyword.get(opts, :lanes, [])
    }
  end

  @impl true
  def init(%SCS{ip: ip, port: port, poll: poll} = state) do
    Global.init!()

    {:ok, conn} = Socket.connect(ip, port)

    :timer.send_after(poll, :poll)

    {
      :ok, 
      state
      |> Map.put(:conn, conn)
      |> configure_lanes()
    }
  end

  @impl true
  def handle_call(:peek, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:status, _from, %{conn: conn} = state) do
    {:reply, Connection.get_real_time_status(conn), state}
  end

  @impl true
  def handle_cast({send_type, msg}, %{conn: conn, sent: sent} = state) do
    case Socket.send(conn, msg, Socket.send(send_type)) do
      {:ok, _msg_number} ->
        {:noreply, Map.put(state, :sent, sent + 1)}
      {:error, _error_number} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:poll, %{conn: conn, poll: poll} = state) do
    Global.poll_callbacks()

    messages = Socket.receive_messages(conn)

    for message <- messages do
      IO.puts(message.payload)
    end

    :timer.send_after(poll, :poll)

    {:noreply, state}
  end

  def handle_info(_, state), do: state

  # PRIVATE FUNCTIONS
  ###################
  defp configure_lanes(%{lanes: []} = state), do: state

  defp configure_lanes(%{lanes: lanes} = state) do
    {:ok, _lanes} = Connection.configure_lanes(state.conn, lanes)

    state
  end
end
