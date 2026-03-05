GameNetworkingSockets.start_server()

amount_clients = 100
amount_sends = 10000

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

# Give time to view receives
:timer.sleep(5000)
