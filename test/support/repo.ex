defmodule CandleClock.Repo do
  use Ecto.Repo,
    otp_app: :candle_clock,
    adapter: Ecto.Adapters.Postgres
end
