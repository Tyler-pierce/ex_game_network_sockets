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
  def configure_connection_lanes(_conn, _priorities, _weights), do: :erlang.nif_error(:not_loaded)
end
