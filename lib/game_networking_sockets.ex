defmodule GameNetworkingSockets do
  @moduledoc """
  Elixir bindings for Valve's GameNetworkingSockets library.

  This library provides a NIF-based interface to the GNS flat C API,
  enabling high-performance game networking from Elixir/Erlang.

  ## Quick Start

      # Initialize the library (once per process)
      GameNetworkingSockets.Global.init!()

      # Server: listen for connections
      {:ok, server} = GameNetworkingSockets.Socket.listen("0.0.0.0", 27015)

      # Client: connect to server
      {:ok, conn} = GameNetworkingSockets.Socket.connect("127.0.0.1", 27015)

      # In your game loop, call these periodically:
      GameNetworkingSockets.Global.poll_callbacks()
      events = GameNetworkingSockets.Global.poll_connection_status_changes()
      messages = GameNetworkingSockets.Socket.receive_messages_on_poll_group(server.poll_group)

      # Send a message
      GameNetworkingSockets.Socket.send(conn, "hello", GameNetworkingSockets.Socket.send_reliable())

      # Cleanup
      GameNetworkingSockets.Global.kill()

  ## Modules

  - `GameNetworkingSockets.Global` — library lifecycle (init/kill/poll)
  - `GameNetworkingSockets.Socket` — listen, connect, accept, send, receive
  - `GameNetworkingSockets.Connection` — connection info and real-time status
  - `GameNetworkingSockets.Nif` — raw NIF bindings (internal)
  """
  alias GameNetworkingSockets.ExSocketManager.{ClientSupervisor, SocketSupervisor}

  @default_server_opts name: :socket_server, poll: 500, ip: "0.0.0.0", port: 27015
  @default_client_opts poll: 500, ip: "127.0.0.1", port: 27015

  @doc """
  Start a GenServer that can respond to Socket requests and maintain a poll

  Opts
    * poll: millisecond polling interval
    * name: atom server name (needs be unique)
    * ip: address to connect socket
    * port: port to connect socket
  """
  def start_server(opts \\ []) do
    Keyword.merge(@default_server_opts, opts)
    |> SocketSupervisor.start_child()
    |> server_added()
  end

  @doc """
  Start a GenServer to host client connection details and provide interface
  to prompt actions or query stats from client

  Opts
    * poll: millisecond polling interval
    * name: atom server name (needs be unique)
    * ip: address to connect socket
    * port: port to connect socket
  """
  def start_client(opts \\ []) do
    @default_client_opts
    |> maybe_generate_name(Keyword.get(opts, :name))
    |> Keyword.merge(opts)
    |> ClientSupervisor.start_child()
    |> client_added()
  end

  def peek(:observer) do
    with {pid, _} <- :syn.lookup(:observers, :global) do
      GenServer.call(pid, :peek)
    end
  end

  # PRIVATE FUNCTIONS
  ###################
  defp server_added({:ok, pid}) do
    with {observer_pid, _} <- :syn.lookup(:observers, :global) do
      GenServer.cast(observer_pid, {:server_added, pid})
    end

    {:ok, pid}
  end

  defp client_added({:ok, pid}) do
    with {observer_pid, _} <- :syn.lookup(:observers, :global) do
      GenServer.cast(observer_pid, {:client_added, pid})
    end

    {:ok, pid}
  end

  defp client_added({:error, _} = error), do: error

  defp maybe_generate_name(opts, nil) do
    # TODO: will replace rand with global Registry
    Keyword.put(opts, :name, :"client_#{:rand.uniform(100000)}")
  end

  defp maybe_generate_name(opts, _name), do: opts
end
