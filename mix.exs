defmodule ParcelRelay.MixProject do
  use Mix.Project

  def project,
    do: [
      app: :parcel_relay,
      version: "0.1.0",
      elixir: ">= 1.20.0",
      deps: deps(),
      dialyzer: [
        plt_local_path: "_build/plts",
        plt_core_path: "_build/plts",
        flags: [:unmatched_returns, :error_handling, :extra_return, :missing_return, :underspecs]
      ]
    ]

  def application, do: [extra_applications: [:logger]]

  defp deps,
    do: [
      {:junit_formatter, ">= 3.4.0", only: :test},
      {:credo, ">= 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 1.4.9", only: [:dev, :test], runtime: false}
    ]
end
