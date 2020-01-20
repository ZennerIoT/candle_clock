use Mix.Config
config :candle_clock, ecto_repos: [CandleClock.Repo]

config :candle_clock, CandleClock.Repo,
  username: "postgres",
  password: "postgres",
  database: "candle_clock_test",
  hostname: "localhost"

