defmodule CandleClock.Worker do
  use GenServer

  import Ecto.Query
  import CandleClock, only: [timer_schema: 0, repo: 0]

  require Logger

  @execution_threshold 150

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  defstruct [
    :timer_ref,
    :task_ref
  ]

  def refresh() do
    GenServer.call(__MODULE__, :refresh_next_trigger)
  end

  def init([]) do
    {:ok, %__MODULE__{}, {:continue, []}}
  end

  def handle_continue(_, state) do
    state = refresh_next_trigger(state)
    {:noreply, state}
  end

  def handle_call(:refresh_next_trigger, _from, state) do
    {:reply, :ok, refresh_next_trigger(state)}
  end

  def handle_info(:execute_timers, state) do
    state =
      state
      |> execute_one()
      |> refresh_next_trigger()

    {:noreply, state}
  end

  defp refresh_next_trigger(state) do
    state = stop_timer(state)

    query = from t in timer_schema(),
      select: t.expires_at,
      where: not t.executing,
      order_by: [asc: t.expires_at],
      limit: 1

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
        %{state | timer_ref: ref}

      diff ->
        Logger.debug("while refreshing next expiry, we found timers that expired #{diff} ms in the past")
        state
        |> execute_one()
        |> refresh_next_trigger()
    end
  end

  defp execute_one(state) do
    repo().transaction(fn ->
      query = from t in timer_schema(),
        where: t.expires_at < ^DateTime.utc_now(),
        where: not t.executing,
        order_by: [asc: t.expires_at],
        limit: 1,
        lock: "FOR UPDATE"

      case repo().one(query) do
        nil ->
          # received no timers, others were faster or unnecessary trigger
          Logger.debug("no timers found")
          nil

        timer ->
          update = from t in timer_schema(),
            where: t.id == ^timer.id,
            update: [set: [executing: true]],
            select: t
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

  defp execute_timer(state, timer) do
    import Ecto.Changeset
    # TODO use a pool
    # TODO what to do with the result? ignore?
    Logger.debug("executing timer #{inspect timer.module}.#{timer.function}(#{Enum.join(Enum.map(timer.arguments, &inspect/1), ", ")})")
    Task.start(timer.module, timer.function, timer.arguments)

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
      query = from t in timer_schema(),
        where: t.id == ^timer.id,
        update: [set: ^updates]

      repo().update_all(query, [])
    end

    state
  end
end
