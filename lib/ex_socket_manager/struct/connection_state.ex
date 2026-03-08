defmodule GameNetworkingSockets.ExSocketManager.Struct.ConnectionChange do
  @moduledoc """
  The connection state change structure as presented by GNS
  """

  defstruct new_state: 0,
    old_state: 0,
    conn: nil,
    end_reason: 0,
    end_debug: []
end
