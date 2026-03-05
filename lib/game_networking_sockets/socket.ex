defmodule GameNetworkingSockets.Socket do
  @moduledoc """
  High-level socket operations for GameNetworkingSockets.

  Provides functions to create server (listen) and client (connect) sockets,
  accept connections, send and receive messages, and manage poll groups.

  ## Send Flags
  Use the constants in this module for the `flags` parameter of `send/3`:
  - `send_unreliable/0` - `0` — may be lost
  - `send_reliable/0` - `8` — guaranteed delivery with retransmission
  - `send_no_nagle/0` - `1` — bypass Nagle buffering
  - `send_no_delay/0` - `4` — drop if can't send quickly
  """

  alias GameNetworkingSockets.Nif

  @doc "Send flag constants matching GNS k_nSteamNetworkingSend_* values"
  def send_unreliable, do: 0
  def send_reliable, do: 8
  def send_no_nagle, do: 1
  def send_no_delay, do: 4

  @doc "convenience to send by atom descriptor"
  def send(:unreliable), do: send_unreliable()
  def send(:reliable), do: send_reliable()
  def send(:no_nagle), do: send_no_nagle()
  def send(:no_delay), do: send_no_delay()

  @doc """
  Create a listen socket (server) bound to the given IP and port.

  Also creates a poll group for receiving messages from all connected clients.

  Returns `{:ok, %{listen_socket: handle, poll_group: handle}}` or `{:error, reason}`.

  ## Example

      {:ok, server} = GameNetworkingSockets.Socket.listen("0.0.0.0", 27015)
  """
  def listen(ip, port) when is_binary(ip) do
    listen(String.to_charlist(ip), port)
  end

  def listen(ip, port) when is_list(ip) and is_integer(port) do
    with {:ok, listen_socket} <- Nif.create_listen_socket_ip(ip, port),
         {:ok, poll_group} <- Nif.create_poll_group() do
      {:ok, %{listen_socket: listen_socket, poll_group: poll_group}}
    end
  end

  @doc """
  Connect to a remote host (client).

  Returns `{:ok, connection_handle}` or `{:error, reason}`.

  ## Example

      {:ok, conn} = GameNetworkingSockets.Socket.connect("127.0.0.1", 27015)
  """
  def connect(ip, port) when is_binary(ip) do
    connect(String.to_charlist(ip), port)
  end

  def connect(ip, port) when is_list(ip) and is_integer(port) do
    Nif.connect_by_ip_address(ip, port)
  end

  @doc """
  Accept an incoming connection and assign it to a poll group.

  Call this when you receive a connection event with `new_state: 1` (Connecting).

  Returns `:ok` or `{:error, result_code}`.
  """
  def accept(conn, poll_group) do
    case Nif.accept_connection(conn) do
      :ok ->
        Nif.set_connection_poll_group(conn, poll_group)
        :ok

      error ->
        error
    end
  end

  @doc """
  Close a connection.

  - `reason` — application-defined reason code (use 0 for normal disconnect)
  - `debug` — debug string (empty string is fine)
  - `linger` — if true, flush pending reliable data before closing
  """
  def close_connection(conn, reason \\ 0, debug \\ "", linger \\ false) do
    Nif.close_connection(conn, reason, String.to_charlist(debug), linger)
  end

  @doc """
  Close a listen socket. No more incoming connections will be accepted.
  """
  def close_listen_socket(listen_socket) do
    Nif.close_listen_socket(listen_socket)
  end

  @doc """
  Destroy a poll group.
  """
  def destroy_poll_group(poll_group) do
    Nif.destroy_poll_group(poll_group)
  end

  @doc """
  Send binary data to a connection.

  `flags` should be a bitmask of send flag constants (e.g. `send_reliable/0`).

  Returns `{:ok, message_number}` or `{:error, result_code}`.

  ## Example

    iex> Socket.send(conn, "hello there", Socket.send_reliable())
    {:ok, 1}
  """
  def send(conn, data, flags) when is_binary(data) do
    Nif.send_message_to_connection(conn, data, flags)
  end

  @doc """
  Flush any pending messages on a connection.
  """
  def flush(conn) do
    Nif.flush_messages_on_connection(conn)
  end

  @doc """
  Receive messages on a single connection.

  Returns a list of message maps, each containing:
  - `:conn` - connection handle
  - `:payload` - binary message data
  - `:message_number` - sequence number
  - `:flags` - send flags
  - `:lane` - lane index
  - `:conn_user_data` - connection user data
  """
  def receive_messages(conn, max \\ 100) do
    Nif.receive_messages_on_connection(conn, max)
  end

  @doc """
  Receive messages on a poll group (all connections in the group).

  Same return format as `receive_messages/2`, but the `:conn` field
  identifies which connection each message came from.
  """
  def receive_messages_on_poll_group(poll_group, max \\ 100) do
    Nif.receive_messages_on_poll_group(poll_group, max)
  end
end
