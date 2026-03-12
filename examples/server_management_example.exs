# Server Management Example
# 
# Example showing OTP of a single node working alongside GNS efficiently handling messages.
# 
# The intent is that OTP will be the bottleneck intentionally to test how much intervention on
# a game servers networking capability is permissable

messaging = :unreliable

# Start servers with 1 millisecond polling
ports = [27015, 27016, 27017, 27018]
amount_ports = length(ports)

server_pids = 
  Enum.map(ports, fn port ->
    {:ok, pid} = GameNetworkingSockets.start_server(
                   name: :"server_#{port}",
                   port: port,
                   poll: 1,
                   handle_poll: GameNetworkingSockets.ExSocketManager.ExampleServerPollNoop
                 )
    
    pid
  end)

amount_clients = 1_000
amount_sends = 1_000_000

# Init clients
clients = Enum.reduce(1..amount_clients, [], fn x, acc ->
            port = Enum.at(ports, rem(x, amount_ports))

            case GameNetworkingSockets.start_client(name: :"client_#{x}", port: port) do
              {:ok, pid} -> [pid | acc]
              _ -> acc
            end
          end)

IO.puts("#{length(clients)} clients created")

IO.puts("Sending #{amount_sends} from random clients")

sender_task = 
  Task.async(fn ->
    1..amount_sends
    |> Task.async_stream(fn _ ->
      clients
      |> Enum.random()
      |> GenServer.cast({messaging, "hello there"})
    end)
    |> Stream.run()
  end)

# 20 second challenge! How many messages can be processed
for polled <- 1..20 do
  :timer.sleep(1000)

  Enum.with_index(server_pids, fn pid, i ->
    state = GenServer.call(pid, :peek)

    IO.puts("Second #{polled}: Server #{i} #{state.messages_received} messages processed")
  end)
end

Task.await(sender_task, :infinity)

total_processed = 
  Enum.reduce(server_pids, 0, fn pid, acc ->
    state = GenServer.call(pid, :peek)

    state.messages_received + acc
  end)

IO.puts("""

Done all processing. #{total_processed} total messages processed

""")
