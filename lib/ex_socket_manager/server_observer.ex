defmodule GameNetworkingSockets.ServerObserver do
  @moduledoc """
  A global observer for tracking and monitoring existing servers and 
  clients
  """
  use GenServer

  def start_link([], opts) do
    GenServer.start_link(
      __MODULE__,
      to_state(opts),
      name: name()
    )
  end

  @doc """
  Fetch process dictionary name of server
  """
  def name(%SCS{name: name}), do: name(name)

  def name(), do: {:via, :syn, {:observers, :global}}

  @doc """
  Create initial state struct of socket server
  """
  def to_state(opts) do
    %SCS{
      name: Keyword.fetch!(opts, :name),
      ip: Keyword.fetch!(opts, :ip),
      port: Keyword.fetch!(opts, :port),
      poll: Keyword.fetch!(opts, :poll)
    }
  end

  @impl true
  def init(%SCS{ip: ip, port: port, poll: poll} = state) do
    Global.init!()

    {:ok, conn} = GameNetworkingSockets.Socket.connect(ip, port)

    :timer.send_after(poll, :poll)

    {:ok, Map.put(state, :conn, conn)}
  end

end
