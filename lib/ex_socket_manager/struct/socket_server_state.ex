defmodule GameNetworkSockets.ExSocketManager.Struct.SocketServerState do
  @moduledoc """
  Defines the socket servers state and how it can be handled
  """

  defstruct name: nil,
    ip: nil,
    port: nil,
    poll: nil,
    timeout: nil
end
