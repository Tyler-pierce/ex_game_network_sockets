defmodule GameNetworkingSocketsTest do
  use ExUnit.Case

  alias GameNetworkingSockets.{Global, Socket}

  test "init and kill lifecycle" do
    assert :ok = Global.init!()
    assert :ok = Global.poll_callbacks()
    assert [] = Global.poll_connection_status_changes()
    assert :ok = Global.kill()
  end

  test "listen and close" do
    Global.init!()

    assert {:ok, %{listen_socket: ls, poll_group: pg}} =
             Socket.listen("127.0.0.1", 47_999)

    assert is_integer(ls)
    assert is_integer(pg)
    assert true = Socket.close_listen_socket(ls)
    assert true = Socket.destroy_poll_group(pg)

    Global.kill()
  end
end
