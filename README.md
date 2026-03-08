# GameNetworkingSockets

High level wrapper for Valve's GameNetworkingSockets.

Game Networking Sockets open source interface is the focus here but some Steam specific functionality is included in an easily distinguishable interface for completeness. Therefore Steam is not required to use this and it can be considered a general use manager and wrapper for Game Networking Sockets.

GNS is made available through NIF calls to their C interface.

**Inspiration:**

(Rust GameNetworkingSockets Wrapper)[https://github.com/hussein-aitlahcen/gns-rs]

## Installation

If there is interest it will be published to hex

```elixir
def deps do
  [
    {:ex_game_networking_sockets, git: "https://github.com/Tyler-pierce/ex_game_network_sockets.git"}
  ]
end
```

To make GameNetworkingSockets available this lib supports the following methods:

1. GNS_PATH env var: point to a local source tree: GNS_PATH=/path/to/GameNetworkingSockets mix compile
2. pkg-config: if GNS was installed via cmake --install or a package manager
3. Fallback: assumes headers in /usr/local/include/steam/ and lib in the default linker path

## What is this for

Another flavor of management over a performant gaming inspired network. The [C#, Rust and Go wrappers around GNS](https://github.com/ValveSoftware/GameNetworkingSockets?tab=readme-ov-file#language-bindings) all have their advantages. ExGameNetworkingSockets brings BEAM/OTP fault tolerance and concurrency.

  * The concurrency model OTP brings is a natural fit for game servers; GNS handles the raw throughput of low latency network calls and the model and tick loop on one BEAM process per server and client makes for easier system design and scale
  * Lobbies, socket management, teams, chats and global features fit well over an OTP cluster
  * Hot code reloading can allow updates to all of that logic without dropping connections
  * Distribution is built in utilizing libcluster + syn

All GNS Servers & Clients poll per their set rates (1 GenServer/BEAM process per GNS Server or Client), the Observer(s) are registered globally to the cluster and can fascilitate moving clients to a machine with an assigned server for example or emiting metrics and stats:

flowchart TD
  subgraph BEAM CLUSTER
    subgraph Machine1
      S1a[GNS Server]
      S1b[GNS Server]
      C1a[GNS Client]
      C1b[GNS Client]
      C1c[GNS Client]
      C1d[GNS Client]
    end

    subgraph Machine2
      S2a[GNS Server]
      C2a[GNS Client]
      C2b[GNS Client]
      C2c[GNS Client]
    end

    subgraph Observer
      S1[Global Server Listings PIDS/Data]
      C1[Global Client Listings PIDS/Data]
    end
  end

  S1a --> C1a
  S1a --> C1b
  S1b --> C1c
  S1b --> C1d

  S2a --> C2a
  S2a --> C2b
  S2a --> C2c

  Observer --> Machine1
  Observer --> Machine2

Note for polling GenServers fastest rate in this system would be per/1millisecond.

This library currency defines a simple libcluster topology for simulating a cluster of 4 machines locally but it can be replaced with [any of their topologies](https://hexdocs.pm/libcluster/readme.html#clustering).

## Included Example Scripts

These will give a good feel for usage:

  * `mix run examples/loopback.exs`: for simple tinkering with GNS more directly
  * `mix run server_management_example.exs`: run a simple load test against the socket management layer

## Basic Concurrency Example

Open 4 terminal tabs:
```
1> iex --name a@127.0.0.1 --cookie nocookie -S mix
2> iex --name b@127.0.0.1 --cookie nocookie -S mix
3> iex --name c@127.0.0.1 --cookie nocookie -S mix
4> iex --name d@127.0.0.1 --cookie nocookie -S mix

iex1> GameNetworkingSockets.start_server()
iex1> {:ok, pid} = GameNetworkingSockets.start_client(lanes: [{0, 1}, {1, 20}, {1, 80}, {2, 1}])
iex1> state = GenServer.call(pid, :peek)
%GameNetworkingSockets.ExSocketManager.Struct.SocketClientState{
  name: :client_75342,
  conn: 366349726,
  ip: "127.0.0.1",
  port: 27015,
  poll: 500,
  sent: 0,
  received: 0,
  lanes: [{0, 1}, {1, 20}, {1, 80}, {2, 1}]
}
iex1> GameNetworkingSockets.Socket.send_messages([{state.conn, "hello there", GameNetworkingSockets.Socket.send_unreliable(), 2}])
[ok: 1]

iex2> GameNetworkingSockets.start_server(port: 27016)

iex3> GameNetworkingSockets.start_server(port: 27017)

iex4> GameNetworkingSockets.start_server(port: 27018)
iex4> GameNetworkingSockets.start_client(port: 27018)
iex4> GameNetworkingSockets.start_client(port: 27018)
iex4> GameNetworkingSockets.peek(:observer)
%GameNetworkingSockets.ExSocketManager.Struct.ServerObserverState{
  servers: %{
    #PID<23955.226.0> => %{
      port: 27017,
      ip: "0.0.0.0",
      server: %{poll_group: 2147549184, listen_socket: 65536}
    },
    #PID<23954.227.0> => %{
      port: 27016,
      ip: "0.0.0.0",
      server: %{poll_group: 2147549184, listen_socket: 65536}
    },
    #PID<0.231.0> => %{
      port: 27018,
      ip: "0.0.0.0",
      server: %{poll_group: 2147549184, listen_socket: 65536}
    },
    #PID<23953.246.0> => %{
      port: 27015,
      ip: "0.0.0.0",
      server: %{poll_group: 2147549184, listen_socket: 65536}
    }
  },
  clients: %{
    #PID<0.233.0> => %{
      name: :client_98195,
      port: 27018,
      ip: "127.0.0.1",
      conn: 2777203108
    },
    #PID<0.234.0> => %{
      name: :client_4591,
      port: 27018,
      ip: "127.0.0.1",
      conn: 1924582012
    },
    #PID<23953.248.0> => %{
      name: :client_75342,
      port: 27015,
      ip: "127.0.0.1",
      conn: 366349726
    }
  },
  nodes: [:"a@127.0.0.1", :"b@127.0.0.1", :"c@127.0.0.1":"d@127.0.0.1"]
}
```
Note that Observer would have been started on node A as the first to start but it is available from any node.

## Steam Networking

This is not tested at this point, I have enough fun playing with GNS! Vibed this into being for completeness and in case anyone else finds it useful. Bring your ideas and I may be happy to help.

## Development & Contribution

Feel free to drop suggestions in issues or use however you'd like.
