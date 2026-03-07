defmodule GameNetworkingSocketsTest do
  use ExUnit.Case

  alias GameNetworkingSockets.{Global, Socket, Connection}

  setup_all do
    :ok = Global.init!()
    on_exit(fn -> Global.kill() end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  test "poll_callbacks returns :ok" do
    assert :ok = Global.poll_callbacks()
  end

  test "poll_connection_status_changes returns a list" do
    events = Global.poll_connection_status_changes()
    assert is_list(events)
  end

  # ---------------------------------------------------------------------------
  # Timestamp
  # ---------------------------------------------------------------------------

  test "get_local_timestamp returns a positive integer" do
    ts = Global.get_local_timestamp()
    assert is_integer(ts)
    assert ts > 0
  end

  test "get_local_timestamp is monotonically increasing" do
    ts1 = Global.get_local_timestamp()
    ts2 = Global.get_local_timestamp()
    assert ts2 >= ts1
  end

  # ---------------------------------------------------------------------------
  # Debug output
  # ---------------------------------------------------------------------------

  test "set_debug_output_level with atom" do
    assert :ok = Global.set_debug_output_level(:warning)
  end

  test "set_debug_output_level with integer" do
    assert :ok = Global.set_debug_output_level(4)
  end

  test "set_debug_output_level rejects invalid atom" do
    assert {:error, :invalid_level} = Global.set_debug_output_level(:nonexistent)
  end

  test "poll_debug_messages returns a list" do
    assert is_list(Global.poll_debug_messages())
  end

  # ---------------------------------------------------------------------------
  # Global config
  # ---------------------------------------------------------------------------

  test "config_keys returns a map" do
    keys = Global.config_keys()
    assert is_map(keys)
    assert Map.has_key?(keys, :fake_packet_lag_send)
  end

  test "set_config_int with atom key" do
    assert :ok = Global.set_config_int(:fake_packet_lag_send, 0)
  end

  test "set_config_int with integer key" do
    assert :ok = Global.set_config_int(4, 0)
  end

  test "set_config_int rejects unknown atom key" do
    assert {:error, :unknown_config_key} = Global.set_config_int(:bogus_key, 0)
  end

  test "set_config_float with atom key" do
    assert :ok = Global.set_config_float(:fake_packet_loss_send, 0.0)
  end

  test "set_config_float rejects unknown atom key" do
    assert {:error, :unknown_config_key} = Global.set_config_float(:bogus_key, 0.0)
  end

  # ---------------------------------------------------------------------------
  # Identity & authentication
  # ---------------------------------------------------------------------------

  test "get_identity returns ok tuple with string" do
    case Global.get_identity() do
      {:ok, identity} -> assert is_list(identity) or is_binary(identity)
      {:error, _} -> :ok
    end
  end

  test "init_authentication returns an integer" do
    result = Global.init_authentication()
    assert is_integer(result)
  end

  test "get_authentication_status returns a map" do
    status = Global.get_authentication_status()
    assert is_map(status)
    assert Map.has_key?(status, :availability)
    assert Map.has_key?(status, :debug_msg)
  end

  test "availability_values returns expected map" do
    vals = Global.availability_values()
    assert is_map(vals)
    assert vals[:current] == 100
    assert vals[:never_tried] == 1
  end

  # ---------------------------------------------------------------------------
  # Relay/ping stubs (open-source build)
  # ---------------------------------------------------------------------------

  test "relay functions return steam_relay_required error" do
    assert {:error, :steam_relay_required} = Global.init_relay_network_access()
    assert {:error, :steam_relay_required} = Global.get_relay_network_status()
    assert {:error, :steam_relay_required} = Global.get_local_ping_location()
    assert {:error, :steam_relay_required} = Global.estimate_ping_between_locations("a", "b")
    assert {:error, :steam_relay_required} = Global.estimate_ping_from_local_host("a")
    assert {:error, :steam_relay_required} = Global.check_ping_data_up_to_date(1.0)
    assert {:error, :steam_relay_required} = Global.get_ping_to_data_center(1)
    assert {:error, :steam_relay_required} = Global.get_direct_ping_to_pop(1)
    assert {:error, :steam_relay_required} = Global.get_pop_count()
    assert {:error, :steam_relay_required} = Global.get_pop_list()
  end

  # ---------------------------------------------------------------------------
  # Steam-only stubs (open-source build)
  # ---------------------------------------------------------------------------

  test "steam-only functions return steamworks_sdk_required error" do
    assert {:error, :steamworks_sdk_required} = SteamNetworking.create_listen_socket_p2p(0)
    assert {:error, :steamworks_sdk_required} = SteamNetworking.connect_p2p("steamid:123", 0)
    assert {:error, :steamworks_sdk_required} = SteamNetworking.received_relay_auth_ticket(<<0>>)
    assert {:error, :steamworks_sdk_required} = SteamNetworking.find_relay_auth_ticket_for_server("steamid:123", 0)
    assert {:error, :steamworks_sdk_required} = SteamNetworking.connect_to_hosted_dedicated_server("steamid:123", 0)
    assert {:error, :steamworks_sdk_required} = SteamNetworking.get_hosted_dedicated_server_port()
    assert {:error, :steamworks_sdk_required} = SteamNetworking.get_hosted_dedicated_server_pop_id()
    assert {:error, :steamworks_sdk_required} = SteamNetworking.get_hosted_dedicated_server_address()
    assert {:error, :steamworks_sdk_required} = SteamNetworking.create_hosted_dedicated_server_listen_socket(0)
    assert {:error, :steamworks_sdk_required} = SteamNetworking.get_game_coordinator_server_login()
  end

  # ---------------------------------------------------------------------------
  # Listen socket
  # ---------------------------------------------------------------------------

  test "listen and close" do
    assert {:ok, %{listen_socket: ls, poll_group: pg}} =
             Socket.listen("127.0.0.1", 47_999)

    assert is_integer(ls)
    assert is_integer(pg)
    assert true = Socket.close_listen_socket(ls)
    assert true = Socket.destroy_poll_group(pg)
  end

  test "get_listen_socket_address returns bound address" do
    {:ok, %{listen_socket: ls, poll_group: pg}} = Socket.listen("127.0.0.1", 48_000)

    assert {:ok, %{address: addr, port: port}} = Socket.get_listen_socket_address(ls)
    assert is_list(addr)
    assert port == 48_000

    Socket.close_listen_socket(ls)
    Socket.destroy_poll_group(pg)
  end

  # ---------------------------------------------------------------------------
  # Socket pair — send, receive, connection info, user data, names
  # ---------------------------------------------------------------------------

  test "create_socket_pair returns two connection handles" do
    assert {:ok, c1, c2} = Socket.create_socket_pair(false)
    assert is_integer(c1)
    assert is_integer(c2)
    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "send and receive through socket pair" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    assert {:ok, _msg_num} = Socket.send(c1, "hello", Socket.send_reliable())
    Global.poll_callbacks()

    msgs = Socket.receive_messages(c2)
    assert length(msgs) >= 1
    msg = hd(msgs)
    assert msg.payload == "hello"
    assert msg.conn == c2

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "connection set/get user_data through socket pair" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    assert true = Connection.set_user_data(c1, 42)
    assert 42 = Connection.get_user_data(c1)

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "connection set/get name through socket pair" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    assert :ok = Connection.set_name(c1, "test-conn")
    assert {:ok, name} = Connection.get_name(c1)
    assert name == ~c"test-conn"

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "connection get_info through socket pair" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    assert {:ok, info} = Connection.get_info(c1)
    assert is_map(info)
    assert Map.has_key?(info, :state)
    assert info.state == 3  # Connected

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "connection get_real_time_status through socket pair" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    assert {:ok, status, _lanes} = Connection.get_real_time_status(c1)
    assert is_map(status)
    assert Map.has_key?(status, :ping)

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "connection get_detailed_status through socket pair" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    assert {:ok, detail} = Connection.get_detailed_status(c1)
    assert is_list(detail)
    assert length(detail) > 0

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "send_messages batch through socket pair" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    results = Socket.send_messages([
      {c1, "msg1", Socket.send_reliable()},
      {c1, "msg2", Socket.send_reliable()}
    ])

    assert length(results) == 2
    assert Enum.all?(results, &match?({:ok, _}, &1))

    Global.poll_callbacks()
    msgs = Socket.receive_messages(c2)
    payloads = Enum.map(msgs, & &1.payload)
    assert "msg1" in payloads
    assert "msg2" in payloads

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  # ---------------------------------------------------------------------------
  # Global get_config_value
  # ---------------------------------------------------------------------------

  test "get_config_value reads global defaults" do
    assert {:ok, value} = Global.get_config_value(:send_buffer_size, :global, 0)
    assert is_integer(value)
    assert value > 0
  end

  test "get_config_value reads global float" do
    # fake_packet_loss_send is a float config (default 0.0)
    case Global.get_config_value(:fake_packet_loss_send, :global, 0) do
      {:ok, val} -> assert is_float(val)
      {:ok, val, :inherited} -> assert is_float(val)
    end
  end

  test "get_config_value returns error for invalid key" do
    assert {:error, :bad_value} = Global.get_config_value(999_999, 1, 0)
  end

  test "get_config_value returns error for unknown atom key" do
    assert {:error, :unknown_key_or_scope} = Global.get_config_value(:bogus, :global, 0)
  end

  test "set then get global config roundtrip" do
    :ok = Global.set_config_int(:fake_packet_lag_send, 50)
    assert {:ok, 50} = Global.get_config_value(:fake_packet_lag_send, :global, 0)
    # Reset
    :ok = Global.set_config_int(:fake_packet_lag_send, 0)
  end

  # ---------------------------------------------------------------------------
  # Per-connection config
  # ---------------------------------------------------------------------------

  test "set and get connection config int" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    assert :ok = Connection.set_config_int(c1, :nagle_time, 0)
    assert {:ok, 0} = Connection.get_config_value(c1, :nagle_time)

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "connection config inherits from global when not set" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    # send_buffer_size should be inherited from global default
    case Connection.get_config_value(c1, :send_buffer_size) do
      {:ok, val} -> assert is_integer(val) and val > 0
      {:ok, val, :inherited} -> assert is_integer(val) and val > 0
    end

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end

  test "connection config rejects unknown atom key" do
    {:ok, c1, c2} = Socket.create_socket_pair(false)
    Global.poll_callbacks()

    assert {:error, :unknown_config_key} = Connection.set_config_int(c1, :bogus, 0)
    assert {:error, :unknown_config_key} = Connection.get_config_value(c1, :bogus)

    Socket.close_connection(c1)
    Socket.close_connection(c2)
  end
end
