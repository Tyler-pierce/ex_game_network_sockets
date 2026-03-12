defmodule GameNetworkingSockets.ExSocketManager.ExampleServerPollNoop do
  @moduledoc """
  Example message handler that does not a thing
  """
  @behaviour GameNetworkingSockets.ExSocketManager.ServerPollBehaviour

  @impl GameNetworkingSockets.ExSocketManager.ServerPollBehaviour
  def connection_status_changes(_changes), do: :ok

  @impl GameNetworkingSockets.ExSocketManager.ServerPollBehaviour
  def messages(_msgs), do: :ok
end
