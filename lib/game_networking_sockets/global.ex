defmodule GameNetworkingSockets.Global do
  @moduledoc """
  Global lifecycle management for GameNetworkingSockets.

  You must call `init!/0` once before using any other functions in this library.
  Call `kill/0` to shut down and release all resources.

  `poll_callbacks/0` must be called periodically (e.g. in a game loop or GenServer)
  to pump the internal GNS callback machinery. Connection status change events
  are buffered internally and can be retrieved with `poll_connection_status_changes/1`.
  """

  alias GameNetworkingSockets.Nif

  @doc """
  Initialize the GameNetworkingSockets library. Must be called once per process lifetime.

  Raises on failure.
  """
  def init! do
    case Nif.gns_init() do
      :ok -> :ok
      {:error, reason} -> raise "GameNetworkingSockets init failed: #{inspect(reason)}"
    end
  end

  @doc """
  Shut down GameNetworkingSockets and release all resources.
  """
  def kill do
    Nif.gns_kill()
  end

  @doc """
  Pump internal GNS callbacks. Must be called periodically.

  This drives the connection state machine — without calling this,
  connection status change events will not fire.
  """
  def poll_callbacks do
    Nif.poll_callbacks()
  end

  @doc """
  Drain buffered connection status change events.

  Returns a list of event maps, each containing:
  - `:conn` - connection handle (integer)
  - `:old_state` - previous connection state (integer)
  - `:new_state` - new connection state (integer)
  - `:end_reason` - reason for connection end (integer, 0 if N/A)
  - `:end_debug` - debug string for connection end

  ## Connection States
  - `0` - None
  - `1` - Connecting
  - `2` - FindingRoute
  - `3` - Connected
  - `4` - ClosedByPeer
  - `5` - ProblemDetectedLocally
  """
  def poll_connection_status_changes(max_events \\ 100) do
    Nif.poll_connection_status_changes(max_events)
  end

  # ---------------------------------------------------------------------------
  # Debug Output
  # ---------------------------------------------------------------------------

  @debug_levels %{
    none: 0,
    bug: 1,
    error: 2,
    important: 3,
    warning: 4,
    msg: 5,
    verbose: 6,
    debug: 7,
    everything: 8
  }

  @doc """
  Set the minimum debug output severity level.

  Messages at or above this severity are buffered and can be
  retrieved with `poll_debug_messages/1`.

  Accepts an integer or one of:
  `:none`, `:bug`, `:error`, `:important`, `:warning`,
  `:msg`, `:verbose`, `:debug`, `:everything`
  """
  def set_debug_output_level(level) when is_atom(level) do
    case Map.fetch(@debug_levels, level) do
      {:ok, int_level} -> Nif.set_debug_output_level(int_level)
      :error -> {:error, :invalid_level}
    end
  end

  def set_debug_output_level(level) when is_integer(level) do
    Nif.set_debug_output_level(level)
  end

  @doc """
  Drain buffered debug output messages.

  Returns a list of maps, each containing:
  - `:type` - severity level (integer)
  - `:msg` - debug message string
  """
  def poll_debug_messages(max \\ 100) do
    Nif.poll_debug_messages(max)
  end

  # ---------------------------------------------------------------------------
  # Global Configuration
  # ---------------------------------------------------------------------------

  @config_keys %{
    fake_packet_loss_send: 2,
    fake_packet_loss_recv: 3,
    fake_packet_lag_send: 4,
    fake_packet_lag_recv: 5,
    fake_packet_reorder_send: 6,
    fake_packet_reorder_recv: 7,
    fake_packet_reorder_time: 8,
    send_buffer_size: 9,
    send_rate_min: 10,
    send_rate_max: 11,
    nagle_time: 12,
    ip_allow_without_auth: 23,
    fake_packet_dup_send: 26,
    fake_packet_dup_recv: 27,
    fake_packet_dup_time_max: 28,
    mtu_packet_size: 32,
    mtu_data_size: 33,
    connection_user_data: 40,
    packet_trace_max_bytes: 41,
    fake_rate_limit_send_rate: 42,
    fake_rate_limit_send_burst: 43,
    fake_rate_limit_recv_rate: 44,
    fake_rate_limit_recv_burst: 45
  }

  @doc """
  Return the map of known config key atoms to their integer enum values.
  """
  def config_keys, do: @config_keys

  @doc """
  Set a global config value (integer).

  `key` can be an atom from `config_keys/0` or a raw integer enum value.

  ## Examples

      # Simulate 100ms send lag
      GameNetworkingSockets.Global.set_config_int(:fake_packet_lag_send, 100)

      # Or use raw enum value
      GameNetworkingSockets.Global.set_config_int(4, 100)
  """
  def set_config_int(key, value) when is_atom(key) do
    case Map.fetch(@config_keys, key) do
      {:ok, int_key} -> Nif.set_global_config_int(int_key, value)
      :error -> {:error, :unknown_config_key}
    end
  end

  def set_config_int(key, value) when is_integer(key) do
    Nif.set_global_config_int(key, value)
  end

  @doc """
  Set a global config value (float).

  ## Examples

      # 10% simulated packet loss
      GameNetworkingSockets.Global.set_config_float(:fake_packet_loss_send, 10.0)
  """
  def set_config_float(key, value) when is_atom(key) do
    case Map.fetch(@config_keys, key) do
      {:ok, int_key} -> Nif.set_global_config_float(int_key, value / 1)
      :error -> {:error, :unknown_config_key}
    end
  end

  def set_config_float(key, value) when is_integer(key) do
    Nif.set_global_config_float(key, value / 1)
  end

  @doc """
  Set a global config value (string).
  """
  def set_config_string(key, value) when is_atom(key) and is_binary(value) do
    case Map.fetch(@config_keys, key) do
      {:ok, int_key} -> Nif.set_global_config_string(int_key, String.to_charlist(value))
      :error -> {:error, :unknown_config_key}
    end
  end

  def set_config_string(key, value) when is_integer(key) and is_binary(value) do
    Nif.set_global_config_string(key, String.to_charlist(value))
  end

  # ---------------------------------------------------------------------------
  # Config Value Read
  # ---------------------------------------------------------------------------

  @config_scopes %{
    global: 1,
    listen_socket: 3,
    connection: 4
  }

  @doc """
  Return the map of config scope atoms to their integer enum values.
  """
  def config_scopes, do: @config_scopes

  @doc """
  Get a configuration value at the specified scope.

  - `key` — config key atom or integer (see `config_keys/0`)
  - `scope` — `:global`, `:listen_socket`, or `:connection` (or integer)
  - `scope_obj` — 0 for global, or a connection/listen socket handle

  Returns `{:ok, value}` if the value is set directly at this scope,
  or `{:ok, value, :inherited}` if using a value inherited from a higher scope.

  The value type is automatically determined — integers, floats, and strings
  are returned as their native Elixir types.

  ## Examples

      # Read global default for send buffer size
      {:ok, 524288} = Global.get_config_value(:send_buffer_size, :global, 0)

      # Read effective value for a specific connection
      {:ok, value} = Global.get_config_value(:nagle_time, :connection, conn)
  """
  def get_config_value(key, scope, scope_obj) when is_atom(key) and is_atom(scope) do
    with {:ok, int_key} <- Map.fetch(@config_keys, key),
         {:ok, int_scope} <- Map.fetch(@config_scopes, scope) do
      Nif.get_config_value(int_key, int_scope, scope_obj)
    else
      :error -> {:error, :unknown_key_or_scope}
    end
  end

  def get_config_value(key, scope, scope_obj) when is_integer(key) and is_integer(scope) do
    Nif.get_config_value(key, scope, scope_obj)
  end

  def get_config_value(key, scope, scope_obj) when is_atom(key) and is_integer(scope) do
    case Map.fetch(@config_keys, key) do
      {:ok, int_key} -> Nif.get_config_value(int_key, scope, scope_obj)
      :error -> {:error, :unknown_config_key}
    end
  end

  def get_config_value(key, scope, scope_obj) when is_integer(key) and is_atom(scope) do
    case Map.fetch(@config_scopes, scope) do
      {:ok, int_scope} -> Nif.get_config_value(key, int_scope, scope_obj)
      :error -> {:error, :unknown_scope}
    end
  end

  # ---------------------------------------------------------------------------
  # Identity & Authentication
  # ---------------------------------------------------------------------------

  @availability %{
    cannot_try: -102,
    failed: -101,
    previously: -100,
    retrying: -10,
    never_tried: 1,
    waiting: 2,
    attempting: 3,
    current: 100,
    unknown: 0
  }

  @doc """
  Return the map of availability enum atom names to integer values.

  Used to interpret values from `init_authentication/0`,
  `get_authentication_status/0`, and `get_relay_network_status/0`.
  """
  def availability_values, do: @availability

  @doc """
  Get the local identity string for this interface.

  Returns `{:ok, identity_string}` or `{:error, :not_available}`.
  """
  def get_identity do
    Nif.get_identity()
  end

  @doc """
  Begin asynchronous authentication initialization.

  Returns an availability integer (see `availability_values/0`).
  """
  def init_authentication do
    Nif.init_authentication()
  end

  @doc """
  Get current authentication status.

  Returns a map with:
  - `:availability` — integer (see `availability_values/0`)
  - `:debug_msg` — human-readable status string
  """
  def get_authentication_status do
    Nif.get_authentication_status()
  end

  @doc """
  Get a certificate request blob for signing by a certificate authority.

  Returns `{:ok, binary_blob}` or `{:error, error_string}`.
  """
  def get_certificate_request do
    Nif.get_certificate_request()
  end

  @doc """
  Install a signed certificate.

  `blob` must be a binary containing the signed certificate.
  Returns `:ok` or `{:error, error_string}`.
  """
  def set_certificate(blob) when is_binary(blob) do
    Nif.set_certificate(blob)
  end

  # ---------------------------------------------------------------------------
  # Relay Network & Ping
  # ---------------------------------------------------------------------------

  @doc """
  Initialize access to the Steam Datagram Relay network.

  Call this early if you anticipate using P2P connections or relay routing.
  Use `get_relay_network_status/0` to monitor initialization progress.
  """
  def init_relay_network_access do
    Nif.init_relay_network_access()
  end

  @doc """
  Get current relay network status.

  Returns a map with:
  - `:availability` — overall availability (integer)
  - `:debug_msg` — human-readable status
  - `:ping_in_progress` — boolean
  - `:network_config` — network config availability (integer)
  - `:any_relay` — relay availability (integer)
  """
  def get_relay_network_status do
    Nif.get_relay_network_status()
  end

  @doc """
  Get the local host's ping location marker.

  Returns `{:ok, location_string, age_seconds}` or `{:error, :not_available}`.

  The location string can be transmitted and used with
  `estimate_ping_between_locations/2` for matchmaking.
  """
  def get_local_ping_location do
    Nif.get_local_ping_location()
  end

  @doc """
  Estimate round-trip latency between two ping location strings.

  Returns ping time in milliseconds, or a negative value on failure.
  """
  def estimate_ping_between_locations(location1, location2)
      when is_binary(location1) and is_binary(location2) do
    Nif.estimate_ping_between_locations(
      String.to_charlist(location1),
      String.to_charlist(location2)
    )
  end

  @doc """
  Estimate round-trip latency from the local host to a remote ping location.

  Returns ping time in milliseconds, or a negative value on failure.
  """
  def estimate_ping_from_local_host(location) when is_binary(location) do
    Nif.estimate_ping_from_local_host(String.to_charlist(location))
  end

  @doc """
  Check if ping data is sufficiently recent, refreshing if needed.

  Returns `true` if data is already up-to-date, `false` if a refresh
  was initiated.
  """
  def check_ping_data_up_to_date(max_age_seconds) do
    Nif.check_ping_data_up_to_date(max_age_seconds / 1)
  end

  # ---------------------------------------------------------------------------
  # Data Centers (POP)
  # ---------------------------------------------------------------------------

  @doc """
  Get ping time to a data center via the relay network.

  Returns `{ping_ms, via_relay_pop_id}`. Negative ping means unavailable.
  """
  def get_ping_to_data_center(pop_id) when is_integer(pop_id) do
    Nif.get_ping_to_data_center(pop_id)
  end

  @doc """
  Get direct ping time to relays at a specific data center.

  Returns ping in milliseconds, or a negative value if unavailable.
  """
  def get_direct_ping_to_pop(pop_id) when is_integer(pop_id) do
    Nif.get_direct_ping_to_pop(pop_id)
  end

  @doc """
  Get the number of data center points of presence in the network config.
  """
  def get_pop_count do
    Nif.get_pop_count()
  end

  @doc """
  Get a list of all data center POP IDs.
  """
  def get_pop_list(max \\ 256) do
    Nif.get_pop_list(max)
  end

  # ---------------------------------------------------------------------------
  # Timestamp
  # ---------------------------------------------------------------------------

  @doc """
  Get the current GNS monotonic timestamp in microseconds.

  Guaranteed monotonic. Initial value is at least ~30 days of microseconds,
  so 0 is always "a long time ago".
  """
  def get_local_timestamp do
    Nif.get_local_timestamp()
  end
end
