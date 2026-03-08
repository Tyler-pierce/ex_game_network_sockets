defmodule GameNetworkingSockets.ExSocketManager.ExampleServerPollPuts do
  @moduledoc """
  Example message handler that simply outputs to IO
  """
  @behaviour GameNetworkingSockets.ExSocketManager.ServerPollBehaviour

  @impl GameNetworkingSockets.ExSocketManager.ServerPollBehaviour
  def connection_status_changes(changes) do
    Enum.each(changes, fn %{old_state: old_state, new_state: new_state, conn: conn} ->
      case {old_state, new_state} do
        {0, 1} -> # New incoming connection — accept it          
          IO.puts("New Connection accepted: #{conn}")

        {1, 3} -> # Connection accepted
          IO.puts("Client connected: #{conn}")

        {_, 4} -> # Closed by peer
          IO.puts("Closed by peer: #{conn}")

        {_, 5} -> # Problem detected locally
          IO.puts("Problem detected locally: #{conn}")

        {from, to} ->
          IO.puts("Unhandled state change #{from} -> #{to}")
      end
    end)

    :ok
  end

  @impl GameNetworkingSockets.ExSocketManager.ServerPollBehaviour
  def messages(msgs) do
    Enum.each(msgs, fn %{payload: payload, lane: lane} ->
      IO.puts("[Message from Lane #{lane}] #{payload}")
    end)
  end
end
