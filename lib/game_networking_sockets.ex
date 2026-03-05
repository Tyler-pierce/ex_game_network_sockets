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
  alias GameNetworkingSockets.ExSocketManager.SocketSupervisor

  @default_server_opts name: :socket_server, poll: 500, ip: "0.0.0.0", port: 27015

  @doc """
  Start a GenServer that can respond to Socket requests and maintain a poll

  Opts
    * poll: millisecond polling interval
    * name: atom server name (needs be unique)
    * ip: address to connect socket
    * port: port to connect socket
  """
  def start_server(opts \\ []) do
    SocketSupervisor.start_child(Keyword.merge(@default_server_opts, opts))
  end
end
