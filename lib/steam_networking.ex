defmodule SteamNetworking do
  @moduledoc """
  Steam-specific networking functions requiring the Steamworks SDK.

  These functions depend on Steam's identity system, Datagram Relay (SDR)
  network, and hosted dedicated server infrastructure. They will return
  errors or no-ops when using the open-source GameNetworkingSockets build
  without Steam.

  ## P2P Connections
  - `create_listen_socket_p2p/1` — listen on a virtual port for P2P connections
  - `connect_p2p/2` — connect to a peer by Steam identity string

  ## Relay Auth Tickets
  - `received_relay_auth_ticket/1` — register a relay auth ticket blob
  - `find_relay_auth_ticket_for_server/2` — find a cached ticket for a server

  ## Hosted Dedicated Servers
  - `connect_to_hosted_dedicated_server/2` — connect via SDR
  - `get_hosted_dedicated_server_port/0`
  - `get_hosted_dedicated_server_pop_id/0`
  - `get_hosted_dedicated_server_address/0`
  - `create_hosted_dedicated_server_listen_socket/1`

  ## Game Coordinator
  - `get_game_coordinator_server_login/0` — get login info for backend
  """

  alias GameNetworkingSockets.Nif

  # ---------------------------------------------------------------------------
  # P2P Connections
  # ---------------------------------------------------------------------------

  @doc """
  Listen for incoming P2P connections on a virtual port.

  Returns `{:ok, listen_socket_handle}` or `{:error, reason}`.

  ## Example

      {:ok, sock} = SteamNetworking.create_listen_socket_p2p(0)
  """
  def create_listen_socket_p2p(virtual_port) when is_integer(virtual_port) do
    Nif.create_listen_socket_p2p(virtual_port)
  end

  @doc """
  Connect to a remote peer by identity string on a virtual port.

  `identity` is a Steam identity string (e.g. `"steamid:76561198000000000"`
  or `"ip:192.168.1.1"`).

  Returns `{:ok, connection_handle}` or `{:error, reason}`.

  ## Example

      {:ok, conn} = SteamNetworking.connect_p2p("steamid:76561198000000000", 0)
  """
  def connect_p2p(identity, virtual_port)
      when is_binary(identity) and is_integer(virtual_port) do
    Nif.connect_p2p(String.to_charlist(identity), virtual_port)
  end

  # ---------------------------------------------------------------------------
  # Relay Auth Tickets
  # ---------------------------------------------------------------------------

  @doc """
  Register a relay auth ticket received from a game coordinator.

  `ticket` is the raw ticket binary blob.

  Returns `{:ok, parsed_ticket_binary}` or `false` if the ticket is invalid.
  The parsed ticket is an opaque binary for inspection purposes only — GNS
  caches the ticket internally for future connections.
  """
  def received_relay_auth_ticket(ticket) when is_binary(ticket) do
    Nif.received_relay_auth_ticket(ticket)
  end

  @doc """
  Find the best cached relay auth ticket for a specific game server.

  Returns `{:ok, seconds_until_expiry, parsed_ticket_binary}` or
  `{:error, :not_found}`.
  """
  def find_relay_auth_ticket_for_server(identity, virtual_port)
      when is_binary(identity) and is_integer(virtual_port) do
    Nif.find_relay_auth_ticket_for_server(String.to_charlist(identity), virtual_port)
  end

  # ---------------------------------------------------------------------------
  # Hosted Dedicated Servers
  # ---------------------------------------------------------------------------

  @doc """
  Connect to a hosted dedicated server via the Steam Datagram Relay network.

  Returns `{:ok, connection_handle}` or `{:error, reason}`.
  """
  def connect_to_hosted_dedicated_server(identity, virtual_port)
      when is_binary(identity) and is_integer(virtual_port) do
    Nif.connect_to_hosted_dedicated_server(String.to_charlist(identity), virtual_port)
  end

  @doc """
  Get the fake port assigned to this hosted dedicated server.

  Returns 0 if not applicable.
  """
  def get_hosted_dedicated_server_port do
    Nif.get_hosted_dedicated_server_port()
  end

  @doc """
  Get the data center POP ID where this dedicated server is hosted.

  Returns 0 if not applicable.
  """
  def get_hosted_dedicated_server_pop_id do
    Nif.get_hosted_dedicated_server_pop_id()
  end

  @doc """
  Get the SDR routing address for this hosted dedicated server.

  Returns `{:ok, routing_binary}` or `{:error, result_code}`.
  The routing binary is an opaque `SteamDatagramHostedAddress` blob.
  """
  def get_hosted_dedicated_server_address do
    Nif.get_hosted_dedicated_server_address()
  end

  @doc """
  Create a listen socket for a hosted dedicated server on a virtual port.

  Returns `{:ok, listen_socket_handle}` or `{:error, reason}`.
  """
  def create_hosted_dedicated_server_listen_socket(virtual_port)
      when is_integer(virtual_port) do
    Nif.create_hosted_dedicated_server_listen_socket(virtual_port)
  end

  # ---------------------------------------------------------------------------
  # Game Coordinator
  # ---------------------------------------------------------------------------

  @doc """
  Get server login info for the game coordinator backend.

  Returns `{:ok, login_info_binary, signed_blob_binary}` or `{:error, reason}`.

  Both returned binaries are opaque — `login_info_binary` contains identity,
  routing, and app info; `signed_blob_binary` is the signed certificate blob
  to send to your game coordinator.
  """
  def get_game_coordinator_server_login do
    Nif.get_game_coordinator_server_login()
  end
end
