defmodule ParcelRelay.MixProject do
  use Mix.Project
  def project, do: [app: :parcel_relay, version: "0.1.0", elixir: ">= 1.20.0", deps: deps()]
  def application, do: [extra_applications: [:logger]]
  defp deps, do: [{:junit_formatter, ">= 3.4.0", only: :test}]
end
