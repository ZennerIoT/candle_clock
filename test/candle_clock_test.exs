defmodule CandleClockTest do
  use CandleClock.DataCase
  doctest CandleClock
  alias CandleClock.Timer

  test "can calculate expiry from duration" do
    timer = %Timer{
      inserted_at: ~U[2020-01-01T13:00:00Z],
      calls: 0,
      duration: 60 * 1000,
    }

    assert {:ok, ~U[2020-01-01T13:01:00Z]} = CandleClock.next_expiry(timer, ~U[2020-01-01T13:00:00Z])
    assert {:ok, ~U[2020-01-01T13:01:00Z]} = CandleClock.next_expiry(timer, ~U[2020-02-01T00:00:00Z])
  end

  test "can calculate expiry from interval" do
    timer = %Timer{
      inserted_at: ~U[2020-01-01T12:00:00Z],
      duration: 5000,
      interval: 10000,
      calls: 3
    }

    assert {:ok, ~U[2020-01-01T13:00:35Z]} = CandleClock.next_expiry(timer, ~U[2020-01-01T13:00:30Z])
    assert {:ok, ~U[2020-01-01T12:00:05Z]} = CandleClock.next_expiry(%{timer | calls: 0}, ~U[2020-01-01T14:00:00Z])
    assert {:ok, ~U[2020-01-01T14:00:05Z]} = CandleClock.next_expiry(%{timer | calls: 1}, ~U[2020-01-01T14:00:00Z])
    assert {:ok, ~U[2020-01-01T12:00:05Z]} = CandleClock.next_expiry(%{timer | calls: 0, skip_if_offline: false}, ~U[2020-01-01T14:00:00Z])
    assert {:ok, ~U[2020-01-01T12:00:05Z]} = CandleClock.next_expiry(%{timer | calls: 0}, ~U[2020-01-01T12:00:00Z])
  end

  test "can calculate expiry from crontab" do
    timer = %Timer{
      inserted_at: ~U[2020-01-01 13:00:00Z],
      crontab: Crontab.CronExpression.Parser.parse!("0 12 15 * *"),
      crontab_timezone: "Europe/Berlin"
    }

    start_at = ~U"2020-04-01 00:00:00Z"
    expected = ~U[2020-04-15 10:00:00.000000Z]

    assert {:ok, ^expected} = CandleClock.next_expiry(timer, start_at)

    expected = ~U[2020-01-15 11:00:00.000000Z]
    assert {:ok, ^expected} = CandleClock.next_expiry(%{timer | skip_if_offline: false}, start_at)
  end

  test "can create timer that expires at a predetermined date" do
    date = ~U[2020-01-01T13:00:00.000000Z]
    assert {:ok, timer} = CandleClock.call_at({__MODULE__, :lol, []}, date)
    assert date = timer.expires_at
    assert {:ok, ^date} = CandleClock.next_expiry(timer, ~U[2020-01-01T13:00:00Z])
  end

  test "create_many/2" do
    now = DateTime.utc_now()
    alarm_date = DateTime.add(now, 2 * 24 * 3600, :second)

    specs = [
      _cron = %{crontab: "0 12 15 * *", crontab_timezone: "Europe/Berlin"},
      _interval = %{interval: 10000, duration: 15000, max_calls: 7, inserted_at: now},
      _duration = %{duration: 5000, max_calls: 1, name: "replace_me", inserted_at: now},
      _date = %{expires_at: alarm_date, max_calls: 1},
    ]

    timers = [_cron, interval, duration, date] = CandleClock.create_many(specs)
    assert duration.expires_at == DateTime.add(now, 5, :second)
    assert date.expires_at == alarm_date
    assert interval.expires_at == DateTime.add(now, 15, :second)
  end
end
