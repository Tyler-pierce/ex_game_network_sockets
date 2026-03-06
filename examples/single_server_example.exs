# Example showing OTP working alongside GNS efficiently handling messages
GameNetworkingSockets.start_server(poll: 10) # 10 millisecond poll

amount_clients = 1000
amount_sends = 1000000

clients = Enum.reduce(1..100, [], fn _, acc ->
            case GameNetworkingSockets.start_client() do
              {:ok, pid} -> [pid | acc]
              _ -> acc
            end
          end)

1..amount_sends
|> Task.async_stream(fn _ -> 
  x = :rand.uniform(amount_clients) - 1
  
  clients
  |> Enum.at(x)
  |> GenServer.cast({:unreliable, "hello there"})
end)
|> Enum.to_list()

# TODO poll server for messages processed

# Keep script alive to complete IO
:timer.sleep(5000)
