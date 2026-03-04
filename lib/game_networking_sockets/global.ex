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
end
