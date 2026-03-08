defmodule GameNetworkingSockets.ExSocketManager.ServerPollBehaviour do
  @moduledoc """
  Behaviour for defining an interface capable of handling all messages received
  by server
  """
  alias GameNetworkingSockets.ExSocketManager.Struct.{ConnectionChange, Message}

  @doc """
  Handle a list of connection status changes
  """
  @callback connection_status_changes(changes :: [%ConnectionChange{}]) :: :ok

  @doc """
  Handle a list of message payloads
  """
  @callback messages(messages :: [%Message{}]) :: :ok
end
