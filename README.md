# CandleClock

`:timer` for ~~cats~~ ecto databases. 

Timers created with CandleClock are stored and tracked in an ecto database. 
This means that timers will now survive restarts of your application.

CandleClock can handle erlang clusters by using row-level locks to isolate the 
next job to be run in each worker.

Timers can have the following types:

 * delay
 * interval
 * cron
 * specific date and time

Read the docs for more in-depth information:
[https://hexdocs.pm/candle_clock](https://hexdocs.pm/candle_clock)

## Installation

The package can be installed by adding `candle_clock` to your list of 
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:candle_clock, "~> 1.4"}
  ]
end
```

