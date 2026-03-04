defmodule GameNetworkingSockets.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_game_networking_sockets,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GameNetworkingSockets.Application, []}
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false},
      {:syn, "~> 3.4"}
    ]
  end
end
