defmodule CandleClockTest do
  use ExUnit.Case
  doctest CandleClock

  test "greets the world" do
    assert CandleClock.hello() == :world
  end
end
