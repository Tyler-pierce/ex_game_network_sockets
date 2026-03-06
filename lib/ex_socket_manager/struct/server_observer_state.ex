defmodule GameNetworkingSockets.ExSocketManager.Struct.ServerObserverState do
  @moduledoc """
  State of the global server observer service
  """

  defstruct servers: %{},
    clients: %{}
end
