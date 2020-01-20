use Mix.Config

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

if Mix.env() == :test do
  import_config("test.exs")
end
