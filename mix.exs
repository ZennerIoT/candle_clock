defmodule CandleClock.MixProject do
  use Mix.Project

  def project do
    [
      app: :candle_clock,
      version: "0.1.1",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: [
        test: [
          # generate the schema to test if schema generation works
          "candle_clock.gen.schema --overwrite test/support/schema.ex",
          "candle_clock.gen.migrations --overwrite",
          "ecto.drop",
          "ecto.create",
          "ecto.migrate",
          # finally, call the tests
          "test"
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, ">= 3.0.0"},
      {:postgrex, "~> 0.15.3", only: :test},
      {:crontab, "~> 1.1"},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false},
      {:tzdata, "~> 1.0"},
      {:jason, "~> 1.1"}
    ]
  end
end
