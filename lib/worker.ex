defmodule CandleClock.Worker do
  use GenServer

  import Ecto.Query
  import CandleClock, only: [timer_schema: 0, repo: 0]

  require Logger

  @execution_threshold 150

  @moduledoc """
  Waits until timers expire and calls them.

  Add this module to your supervisor-tree once.
  """

  @doc """
  Starts the CandleClock worker.
  """
  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_link(_) do
    start_link()
  end

  defstruct [
    :timer_ref,
    :task_ref,
    :expires_at
  ]

  def next_expiry_query() do
    from(t in timer_schema(),
      select: t.expires_at,
      where: not t.executing or t.expires_at < ago(1, "month"),
      order_by: [asc: t.expires_at],
      limit: 1
    )
  end

  @doc """
  Refreshes the internal timer until the next invocation for the current node.
  """
  def refresh() do
    query = next_expiry_query()

    case repo().one(query) do
      nil ->
        {:ok, nil}

      expires_at ->
        GenServer.call(__MODULE__, {:set_next_expiry, expires_at})
    end
  end

  def set_next_expiry(expires_at) do
    GenServer.call(__MODULE__, {:set_next_expiry, expires_at})
  end

  @doc false
  def init([]) do
    {:ok, %__MODULE__{}, {:continue, []}}
  end

  @doc false
  def handle_continue(_, state) do
    state = repo().checkout(fn -> refresh_next_trigger(state) end)
    {:noreply, state}
  end

  @doc false
  def handle_call({:set_next_expiry, expires_at}, _from, state) do
    state =
      repo().checkout(fn ->
        case state.expires_at do
          nil ->
            start_timer(state, expires_at)

          old_expires_at ->
            case DateTime.compare(old_expires_at, expires_at) do
              :gt ->
                start_timer(state, expires_at)

              _lt_or_eq ->
                state
            end
        end
      end)

    {:reply, :ok, state}
  end

  @doc false
  def handle_info(:execute_timers, state) do
    state =
      repo().checkout(fn ->
        state
        |> execute_one()
        |> refresh_next_trigger()
      end)

    {:noreply, state}
  end

  defp refresh_next_trigger(state) do
    state = stop_timer(state)

    query = next_expiry_query()

    case repo().one(query) do
      nil ->
        state

      expires_at ->
        start_timer(state, expires_at)
    end
  end

  defp stop_timer(state) do
    if state.timer_ref do
      {:ok, :cancel} = :timer.cancel(state.timer_ref)
      %{state | timer_ref: nil}
    else
      state
    end
  end

  defp start_timer(state, expires_at) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :millisecond) do
      diff when diff > @execution_threshold ->
        Logger.debug("next expiry at #{expires_at} in #{diff} ms")
        {:ok, ref} = :timer.send_after(diff, :execute_timers)
        %{state | timer_ref: ref, expires_at: expires_at}

      diff ->
        Logger.debug(
          "while refreshing next expiry, we found timers that expired #{diff} ms in the past"
        )


        repo().checkout(fn ->
          state
          |> execute_one()
          |> refresh_next_trigger()
        end)
    end
  end

  defp execute_one(state) do
    repo().transaction(fn ->
      query =
        from(t in timer_schema(),
          where: t.expires_at < ^DateTime.utc_now(),
          where: not t.executing or t.expires_at < ago(1, "hour"),
          order_by: [asc: t.expires_at],
          limit: 1,
          lock: "FOR UPDATE"
        )

      case repo().one(query) do
        nil ->
          # received no timers, others were faster or unnecessary trigger
          Logger.debug("no timers found")
          nil

        timer ->
          update =
            from(t in timer_schema(),
              where: t.id == ^timer.id,
              update: [set: [executing: true]],
              select: t
            )

          case repo().update_all(update, []) do
            {1, [timer]} -> timer
            _ -> raise RuntimeError
          end
      end
    end)
    |> case do
      {:ok, nil} -> state
      {:ok, timer} -> execute_timer(state, timer)
      {:error, error} -> raise error
    end
  end

  def execute_timer(state, timer) do
    # TODO use a pool
    # TODO what to do with the result? ignore?
    Logger.debug(
      "executing timer #{inspect(timer.module)}.#{timer.function}(#{Enum.join(Enum.map(timer.arguments, &inspect/1), ", ")})"
    )

    Task.start(fn ->
      Logger.metadata(timer: timer)
      apply(timer.module, timer.function, timer.arguments)
    end)

    {:ok, expires_at} = CandleClock.next_expiry(timer)
    diff = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond)

    Logger.debug("next expiry at #{expires_at}, #{diff} ms from now")

    timer =
      timer
      |> Map.merge(%{expires_at: expires_at, executing: false})
      |> Map.update!(:calls, &(&1 + 1))

    if timer.calls >= timer.max_calls do
      {:ok, _} = repo().delete(timer)
    else
      updates = Map.take(timer, [:expires_at, :executing, :calls]) |> Enum.into([])

      query =
        from(t in timer_schema(),
          where: t.id == ^timer.id,
          update: [set: ^updates]
        )

      repo().update_all(query, [])
    end

    %{state | expires_at: nil}
  end
end
