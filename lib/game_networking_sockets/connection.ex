defmodule GameNetworkingSockets.Connection do
  @moduledoc """
  Connection information and status queries.

  ## Connection States
  - `0` - None (invalid/closed)
  - `1` - Connecting
  - `2` - FindingRoute
  - `3` - Connected
  - `4` - ClosedByPeer
  - `5` - ProblemDetectedLocally
  """

  alias GameNetworkingSockets.Nif

  @doc """
  Get detailed info about a connection.

  Returns `{:ok, info_map}` or `{:error, reason}`.

  The info map contains:
  - `:state` - connection state (integer)
  - `:end_reason` - end reason code
  - `:end_debug` - debug string for end reason
  - `:remote_address` - remote IP as string
  - `:remote_port` - remote port
  - `:user_data` - user data (int64)
  - `:listen_socket` - associated listen socket handle (0 if client-initiated)
  - `:flags` - connection info flags
  - `:connection_description` - internal debug description
  """
  def get_info(conn) do
    Nif.get_connection_info(conn)
  end

  @doc """
  Get real-time connection status (ping, quality, throughput, etc.).

  Returns `{:ok, status_map, lanes_list}` or `{:error, result_code}`.

  The status map contains:
  - `:state` - connection state
  - `:ping` - current ping in ms
  - `:quality_local` - local quality estimate (0.0–1.0)
  - `:quality_remote` - remote quality estimate (0.0–1.0)
  - `:out_packets_per_sec` / `:out_bytes_per_sec`
  - `:in_packets_per_sec` / `:in_bytes_per_sec`
  - `:send_rate_bytes_per_sec` - estimated send capacity
  - `:pending_unreliable` / `:pending_reliable` - bytes pending
  - `:sent_unacked_reliable` - reliable bytes awaiting ack
  - `:queue_time_usec` - estimated queue delay in microseconds
  """
  def get_real_time_status(conn, num_lanes \\ 0) do
    Nif.get_connection_real_time_status(conn, num_lanes)
  end

  @doc """
  Set arbitrary user data on a connection (int64).
  """
  def set_user_data(conn, user_data) do
    Nif.set_connection_user_data(conn, user_data)
  end

  @doc """
  Get user data previously set on a connection.

  Returns the int64 user data value. Returns -1 if the connection
  is invalid or user data was never set (default is -1).
  """
  def get_user_data(conn) do
    Nif.get_connection_user_data(conn)
  end

  @doc """
  Get a detailed human-readable text dump of connection status and statistics.

  Returns `{:ok, status_string}` or `{:error, reason}`.

  Useful for debugging — the output includes ping, throughput, packet loss,
  and other diagnostic information.
  """
  def get_detailed_status(conn) do
    Nif.get_detailed_connection_status(conn)
  end

  @doc """
  Set a debug name for a connection.

  This name appears in debug output and `get_info/1` connection descriptions.
  """
  def set_name(conn, name) when is_binary(name) do
    Nif.set_connection_name(conn, String.to_charlist(name))
  end

  @doc """
  Get the debug name of a connection.

  Returns `{:ok, name_string}` or `{:error, reason}`.
  """
  def get_name(conn) do
    Nif.get_connection_name(conn)
  end

  @doc """
  Configure connection lanes for priority/weighted message sending.

  `lanes` is a list of `{priority, weight}` tuples.
  """
  def configure_lanes(conn, lanes) when is_list(lanes) do
    {priorities, weights} = Enum.unzip(lanes)

    Nif.configure_connection_lanes(conn, priorities, weights)
  end
end
