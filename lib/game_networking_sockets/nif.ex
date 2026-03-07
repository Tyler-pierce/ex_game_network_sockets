defmodule GameNetworkingSockets.Nif do
  @moduledoc false
  @on_load :load_nif

  defp load_nif do
    path = :filename.join(:code.priv_dir(:ex_game_networking_sockets), ~c"gns_nif")
    :erlang.load_nif(path, 0)
  end

  # Global lifecycle
  def gns_init, do: :erlang.nif_error(:not_loaded)
  def gns_kill, do: :erlang.nif_error(:not_loaded)

  # Callbacks
  def poll_callbacks, do: :erlang.nif_error(:not_loaded)
  def poll_connection_status_changes(_max_events), do: :erlang.nif_error(:not_loaded)

  # Listen sockets
  def create_listen_socket_ip(_ip, _port), do: :erlang.nif_error(:not_loaded)
  def close_listen_socket(_socket), do: :erlang.nif_error(:not_loaded)

  # Connections
  def connect_by_ip_address(_ip, _port), do: :erlang.nif_error(:not_loaded)
  def accept_connection(_conn), do: :erlang.nif_error(:not_loaded)
  def close_connection(_conn, _reason, _debug, _linger), do: :erlang.nif_error(:not_loaded)

  # Poll groups
  def create_poll_group, do: :erlang.nif_error(:not_loaded)
  def destroy_poll_group(_poll_group), do: :erlang.nif_error(:not_loaded)
  def set_connection_poll_group(_conn, _poll_group), do: :erlang.nif_error(:not_loaded)

  # Messaging
  def send_message_to_connection(_conn, _data, _flags), do: :erlang.nif_error(:not_loaded)
  def flush_messages_on_connection(_conn), do: :erlang.nif_error(:not_loaded)
  def receive_messages_on_connection(_conn, _max), do: :erlang.nif_error(:not_loaded)
  def receive_messages_on_poll_group(_poll_group, _max), do: :erlang.nif_error(:not_loaded)

  # Connection info
  def get_connection_info(_conn), do: :erlang.nif_error(:not_loaded)
  def get_connection_real_time_status(_conn, _num_lanes), do: :erlang.nif_error(:not_loaded)
  def set_connection_user_data(_conn, _user_data), do: :erlang.nif_error(:not_loaded)
  def get_connection_user_data(_conn), do: :erlang.nif_error(:not_loaded)
  def configure_connection_lanes(_conn, _priorities, _weights), do: :erlang.nif_error(:not_loaded)
  def get_detailed_connection_status(_conn), do: :erlang.nif_error(:not_loaded)
  def set_connection_name(_conn, _name), do: :erlang.nif_error(:not_loaded)
  def get_connection_name(_conn), do: :erlang.nif_error(:not_loaded)

  # Listen socket info
  def get_listen_socket_address(_socket), do: :erlang.nif_error(:not_loaded)

  # Batch messaging
  def send_messages(_messages), do: :erlang.nif_error(:not_loaded)

  # Debug output
  def set_debug_output_level(_level), do: :erlang.nif_error(:not_loaded)
  def poll_debug_messages(_max), do: :erlang.nif_error(:not_loaded)

  # Global config
  def set_global_config_int(_key, _value), do: :erlang.nif_error(:not_loaded)
  def set_global_config_float(_key, _value), do: :erlang.nif_error(:not_loaded)
  def set_global_config_string(_key, _value), do: :erlang.nif_error(:not_loaded)

  # Per-connection config
  def set_connection_config_int(_conn, _key, _value), do: :erlang.nif_error(:not_loaded)
  def set_connection_config_float(_conn, _key, _value), do: :erlang.nif_error(:not_loaded)
  def set_connection_config_string(_conn, _key, _value), do: :erlang.nif_error(:not_loaded)

  # Config value read
  def get_config_value(_key, _scope, _scope_obj), do: :erlang.nif_error(:not_loaded)

  # Socket pair
  def create_socket_pair(_use_network_loopback), do: :erlang.nif_error(:not_loaded)

  # Identity & authentication
  def get_identity, do: :erlang.nif_error(:not_loaded)
  def init_authentication, do: :erlang.nif_error(:not_loaded)
  def get_authentication_status, do: :erlang.nif_error(:not_loaded)
  def get_certificate_request, do: :erlang.nif_error(:not_loaded)
  def set_certificate(_blob), do: :erlang.nif_error(:not_loaded)

  # Relay network
  def init_relay_network_access, do: :erlang.nif_error(:not_loaded)
  def get_relay_network_status, do: :erlang.nif_error(:not_loaded)

  # Ping location
  def get_local_ping_location, do: :erlang.nif_error(:not_loaded)
  def estimate_ping_between_locations(_loc1, _loc2), do: :erlang.nif_error(:not_loaded)
  def estimate_ping_from_local_host(_loc), do: :erlang.nif_error(:not_loaded)
  def check_ping_data_up_to_date(_max_age), do: :erlang.nif_error(:not_loaded)

  # Data center / POP
  def get_ping_to_data_center(_pop_id), do: :erlang.nif_error(:not_loaded)
  def get_direct_ping_to_pop(_pop_id), do: :erlang.nif_error(:not_loaded)
  def get_pop_count, do: :erlang.nif_error(:not_loaded)
  def get_pop_list(_max), do: :erlang.nif_error(:not_loaded)

  # Timestamp
  def get_local_timestamp, do: :erlang.nif_error(:not_loaded)

  # Steam-only: P2P, Relay, Hosted Dedicated Server, Game Coordinator
  def create_listen_socket_p2p(_virtual_port), do: :erlang.nif_error(:not_loaded)
  def connect_p2p(_identity, _virtual_port), do: :erlang.nif_error(:not_loaded)
  def received_relay_auth_ticket(_ticket), do: :erlang.nif_error(:not_loaded)
  def find_relay_auth_ticket_for_server(_identity, _virtual_port), do: :erlang.nif_error(:not_loaded)
  def connect_to_hosted_dedicated_server(_identity, _virtual_port), do: :erlang.nif_error(:not_loaded)
  def get_hosted_dedicated_server_port, do: :erlang.nif_error(:not_loaded)
  def get_hosted_dedicated_server_pop_id, do: :erlang.nif_error(:not_loaded)
  def get_hosted_dedicated_server_address, do: :erlang.nif_error(:not_loaded)
  def create_hosted_dedicated_server_listen_socket(_virtual_port), do: :erlang.nif_error(:not_loaded)
  def get_game_coordinator_server_login, do: :erlang.nif_error(:not_loaded)
end
