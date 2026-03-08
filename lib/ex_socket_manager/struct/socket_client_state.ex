defmodule GameNetworkingSockets.ExSocketManager.Struct.SocketClientState do
  @moduledoc """
  Defines the socket clients state and how it can be handled
  """

  defstruct name: nil,
    conn: nil,
    ip: nil,
    port: nil,
    poll: nil,
    sent: 0,
    received: 0,
    lanes: []
end
