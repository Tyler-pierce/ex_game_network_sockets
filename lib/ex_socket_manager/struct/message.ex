defmodule GameNetworkingSockets.ExSocketManager.Struct.Message do
  @moduledoc """
  The message structure as presented by GNS
  """

  defstruct flags: 0,
    payload: "",
    conn: nil,
    message_number: 0,
    lane: 0,
    conn_user_data: -1
end
