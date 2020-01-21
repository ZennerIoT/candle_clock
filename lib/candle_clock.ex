defmodule CandleClock do
  @type argument :: any
  @type arguments :: [argument]
  @type mf_args :: {module, atom, arguments}
  @type interval :: non_neg_integer

  @spec timer_schema() :: module
  def timer_schema do
    Application.get_env(:candle_clock, :timer_schema, CandleClock.Timer)
  end

  def repo do
    Application.get_env(:candle_clock, :repo, CandleClock.Repo)
  end

  @spec call_after(mf_args, interval, keyword) :: {:ok, struct} | {:error, any}
  def call_after(mfa, duration, opts \\ []) do
    create(mfa, %{
      duration: duration,
      max_calls: 1
    }, opts)
  end

  def call_interval(mfa, duration \\ nil, interval, opts \\ []) do
    duration = duration || interval
    create(mfa, %{
      duration: duration,
      interval: interval
    }, opts)
  end

  def call_crontab(mfa, crontab, timezone \\ "Etc/UTC", opts \\ []) do
    with {:ok, crontab} <- Crontab.CronExpression.Parser.parse(crontab) do
      create(mfa, %{
        crontab: crontab,
        crontab_timezone: timezone
      }, opts)
    end
  end

  def cancel_by_id(id) do

  end

  def cancel_by_name(name) do

  end

  def cancel_all(module, function) do

  end

  @spec create(mf_args, map, keyword) :: {:ok, struct} | {:error, term}
  defp create({m, f, a}, params, opts) do
    now = DateTime.utc_now()
    defaults = %{
      module: m,
      function: f,
      arguments: a,
      inserted_at: now,
      updated_at: now
    }
    params = Enum.reduce([Enum.into(opts, %{}), defaults, params], %{}, &Map.merge/2)
    timer = struct(timer_schema(), params)

    with {:ok, expires_at} <- next_expiry(timer, now),
         timer = Map.put(timer, :expires_at, expires_at),
         {:ok, timer} <- repo().insert(timer, on_conflict: :replace_all, conflict_target: [:name]),
         refresh_next_timer() do
      {:ok, timer}
    end
  end

  defp refresh_next_timer() do
    :rpc.multicall(CandleClock.Worker, :refresh, [])
  end

  @spec next_expiry(struct, DateTime.t) :: {:ok, DateTime.t} | {:error, any}
  def next_expiry(timer, date \\ DateTime.utc_now())

  def next_expiry(%{skip_if_offline: true} = timer, date) do
    case timer do
      %{duration: duration, calls: 0} when not is_nil(duration) ->
        next = DateTime.add(timer.inserted_at, duration, :millisecond)
        {:ok, next}

      %{interval: interval, calls: calls} when not is_nil(interval) and calls >= 1 ->
        start_at = DateTime.add(timer.inserted_at, timer.duration, :millisecond)
        res = get_next_interval_after(start_at, date, interval)
        {:ok, res}

      %{crontab: crontab} when not is_nil(crontab) ->
        with {:ok, date} <- DateTime.shift_zone(date, timer.crontab_timezone),
             naive = DateTime.to_naive(date),
             {:ok, naive} <- Crontab.Scheduler.get_next_run_date(crontab, naive),
             {:ok, with_tz} <- DateTime.from_naive(naive, timer.crontab_timezone) do
          with_tz = Map.put(with_tz, :microsecond, {0, 6})
          DateTime.shift_zone(with_tz, "Etc/UTC")
        end
    end
  end

  def next_expiry(%{skip_if_offline: false} = timer, _date) do
    date = timer.expires_at || timer.inserted_at
    next_expiry(%{timer | skip_if_offline: true}, date)
  end

  def get_next_interval_after(start_at, date, interval) do
    next = DateTime.add(start_at, interval, :millisecond)

    case DateTime.compare(date, next) do
      :gt -> get_next_interval_after(next, date, interval)
      :lt -> next
      :eq -> next
    end
  end
end
