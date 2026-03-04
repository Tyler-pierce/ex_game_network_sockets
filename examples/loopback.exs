alias GameNetworkingSockets.{Global, Socket}

port = 27015

# 1. Init
Global.init!()

# 2. Server listens
{:ok, server} = Socket.listen("0.0.0.0", port)
IO.puts("Server listening on port #{port}")

# 3. Client connects
{:ok, client_conn} = Socket.connect("127.0.0.1", port)
IO.puts("Client connecting... (conn=#{client_conn})")

# 4. Poll until we see the incoming connection, then accept it
:timer.sleep(50)
Global.poll_callbacks()

for event <- Global.poll_connection_status_changes() do
  IO.puts("Event: conn=#{event.conn} old=#{event.old_state} new=#{event.new_state}")

  # Accept incoming connections (the ones we did NOT initiate)
  if event.conn != client_conn and event.new_state == 1 do
    :ok = Socket.accept(event.conn, server.poll_group)
    IO.puts("Accepted server-side connection #{event.conn}")
  end
end

# 5. Poll a few times to let the handshake complete
for _ <- 1..10 do
  :timer.sleep(20)
  Global.poll_callbacks()
end

# Drain events to see Connected status
for event <- Global.poll_connection_status_changes() do
  IO.puts("Event: conn=#{event.conn} old=#{event.old_state} new=#{event.new_state}")
end

# 6. Send a message from client to server
{:ok, msg_num} = Socket.send(client_conn, "hello from elixir!", Socket.send_reliable())
IO.puts("Sent message ##{msg_num}")

# 7. Poll and receive on the server's poll group
:timer.sleep(50)
Global.poll_callbacks()

messages = Socket.receive_messages_on_poll_group(server.poll_group)
IO.puts("Server received #{length(messages)} message(s)")

for msg <- messages do
  IO.puts("  payload: #{inspect(msg.payload)}")
end

# 8. Cleanup
Socket.close_connection(client_conn)
Socket.close_listen_socket(server.listen_socket)
Socket.destroy_poll_group(server.poll_group)
Global.kill()
IO.puts("Done.")
