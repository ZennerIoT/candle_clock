defmodule CandleClock do
  require Logger
  import Ecto.Query

  @type argument :: any
  @type arguments :: [argument]
  @type mf_args :: {module, atom, arguments}
  @type interval :: non_neg_integer

  @moduledoc """
  CandleClock manages timers that persist even across restarts.

  ## Core concepts

  ### Timer

  A **timer** is a function call that will happen at some point in the future.
  It always contains an [MFA](#module-mfa) and
  either a duration, an interval or a crontab expression.

  ### MFA

  An **MFA** is a tuple with 3 elements: the module, the function and the
  arguments to pass to the function. The 3 elements of the tuple are the same as
  the 3 arguments you'd pass to `Kernel.apply/3`.

  ### Crontab

  A **crontab** expression can be used when you want the timer to trigger at
  regular dates or times, such as

   * Every monday at 12 AM: `0 12 * * 1`
   * Every 5 minutes: `*/5 * * * *`
   * Every hour: `0 * * * *`
   * Every day at 5 PM: `0 17 * * *`

  Timers with crontabs can be given an additional time zone so `0 17 * * *` for
  `Europe/Berlin` is 16:00 UTC during winter time but 15:00 UTC during summer
  time.

  ### Startup behaviour

  At startup, all timers that have an `expired_at` date in the past will be
  executed.

  When planning the next execution time of a single timer, it will take the last
  execution time as the basis. However, that might lead to a timer being called
  multiple times directly after a long downtime.

  For that reason, if `:skip_if_offline` is true, interval and cron timers will
  instead be planned to the next time it would've happened as if the earlier
  intervals would've been triggered as well, but they won't be called more than
  once at startup.

  `:skip_if_offline` is enabled by default.

  ### Duration and intervals

  All durations and intervals are integers in the unit millisecond.

  ## Common options

  These are the common options that can be passed to `call_after/3`,
  `call_interval/4` and `call_crontab/4`:

   * `:name` (string) A name that makes this timer unique. Unique timers will
     be replaced when a new timer with the same name is created. That way, a
     defer can be implemented simply by always giving the same name.
   * `:skip_if_offline` (bool, default: `true`) If set to false, interval and
     cron timers behave differently after a long downtime of the system. See
     also: [Startup behaviour](#module-startup-behaviour)
   * `:max_calls` (int, default: `nil` or `1` for duration timers) Controls the
     maximum amount this timer can be called before it is cancelled. Not
     supported in duration timers started with `call_after/3`.
  """

  @doc false
  @spec timer_schema() :: module
  def timer_schema do
    Application.get_env(:candle_clock, :timer_schema, CandleClock.Timer)
  end

  @doc false
  def repo do
    Application.get_env(:candle_clock, :repo, CandleClock.Repo)
  end

  @doc """
  Creates a timer that is executed after the duration in milliseconds.

  Returns the timer in an ok-tuple if successful.
  """
  @spec call_after(mf_args, interval, keyword) :: {:ok, struct} | {:error, any}
  def call_after(mfa, duration, opts \\ []) do
    create(mfa, %{
      duration: duration,
      max_calls: 1
    }, opts)
  end

  @doc """
  Creates a timer that is executed every `interval` ms.

  Additionally, the duration until the first trigger can be passed with the
  `duration` argument.

  Returns the timer in an ok-tuple if successful.
  """
  @spec call_interval(mf_args, interval, interval, keyword) :: {:ok, struct} | {:error, any}
  def call_interval(mfa, duration \\ nil, interval, opts \\ []) do
    duration = duration || interval
    create(mfa, %{
      duration: duration,
      interval: interval
    }, opts)
  end

  @doc """
  Creates a timer that is executed according to the given crontab schema.

  Returns the timer in an ok-tuple if successful.
  """
  @spec call_crontab(mf_args, String.t, String.t, keyword) :: {:ok, struct} | {:error, any}
  def call_crontab(mfa, crontab, timezone \\ "Etc/UTC", opts \\ []) do
    with {:ok, crontab} <- Crontab.CronExpression.Parser.parse(crontab) do
      create(mfa, %{
        crontab: crontab,
        crontab_timezone: timezone
      }, opts)
    end
  end

  @doc """
  Cancels a timer by its ID.

  Returns `{:ok, 1}` if the ID matched.
  """
  @spec cancel_by_id(any) :: {:ok, non_neg_integer}
  def cancel_by_id(id) do
    query = from t in timer_schema(),
      where: t.id == ^id
    cancel_by_query(query)
  end

  @doc """
  Cancels the timer with the given name.

  Returns `{:ok, 1}` if a timer with that name was found.
  """
  @spec cancel_by_name(String.t) :: {:ok, non_neg_integer}
  def cancel_by_name(name) do
    query = from t in timer_schema(),
      where: t.name == ^name
    cancel_by_query(query)
  end

  @doc """
  Cancels all timers that call the given module and function.

  Returns `{:ok, amount}` if successful, where amount is the number of timers
  that were cancelled.
  """
  @spec cancel_all(module, atom) :: {:ok, non_neg_integer}
  def cancel_all(module, function) do
    query = from t in timer_schema(),
      where: t.module == ^module,
      where: t.function == ^function
    cancel_by_query(query)
  end

  defp cancel_by_query(query) do
    {num, _} = repo().delete_all(query)
    Logger.debug("Cancelled #{num} timers")
    refresh_next_timer()
    {:ok, num}
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


  @doc """
  Calculates the next expiry date for the given timer from the given date
  onwards.

  Returns `{:ok, datetime}` or an error-tuple
  """
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

  defp get_next_interval_after(start_at, date, interval) do
    next = DateTime.add(start_at, interval, :millisecond)

    case DateTime.compare(date, next) do
      :gt -> get_next_interval_after(next, date, interval)
      :lt -> next
      :eq -> next
    end
  end
end
