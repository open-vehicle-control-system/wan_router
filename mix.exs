defmodule WanRouter.MixProject do
  use Mix.Project

  @app :wan_router
  @version "0.1.0"
  @all_targets [:nerves_system_fairphone2]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      archives: [nerves_bootstrap: "~> 1.15"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [{@app, release()}]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {WanRouter.Application, []}
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies for all targets
      {:nerves, "~> 1.13", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:logger_backends, "~> 1.0"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.5.0"},

      # Allow Nerves.Runtime on host to support development, testing and CI.
      # See config/host.exs for usage.
      {:nerves_runtime, "~> 0.13.12"},

      # Dependencies for all targets except :host
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},

      # 4G uplink: VintageNet QMI tech + the QMI library it sits on.
      # Both pinned to mlainez's `main` (upstream + APN/auth/PDP-type extensions);
      # pulls the upstream version transitively.
      {:vintage_net_qmi, github: "mlainez/vintage_net_qmi", branch: "main", targets: @all_targets},
      {:qmi, github: "mlainez/qmi", branch: "main", override: true, targets: @all_targets},

      # Brings up udevd (so kernel hotplug populates /dev for the modem
      # remoteproc) and rmtfs (so the modem can reach its NV partitions)
      # before VintageNet tries to configure wwan0.
      {:ex_rmtfs, github: "mlainez/ex_rmtfs", branch: "main", targets: @all_targets},
      {:nerves_system_fairphone2, github: "Spin42/nerves_system_fairphone2", tag: "v1.35.3", runtime: false, targets: @all_targets}
    ]
  end

  def release do
    [
      overwrite: true,
      # Erlang distribution is not started automatically.
      # See https://nerves-pack.hexdocs.pm/readme.html#erlang-distribution
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end
end
