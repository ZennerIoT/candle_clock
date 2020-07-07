defmodule CandleClock.ErrorLogger do
  require Logger

  @type message :: binary | [message]
  @type kind :: :error | :exit
  @type error :: any

  @doc """
  Formats and logs the given error using `Exception.format/3` and `Logger.error/1`.

  Depending on from where this macro is called, it will also include
  the stacktrace that was recorded with the error in the log message.

  `error` can be anything, special formatting will be done for certain Erlang error atoms or tuples,
  as well as Elixir exceptions.

  `log_level` (default `:error`) can be overwritten to log in a different level

  `metadata` optional metadata passed into the Logger
  """
  defmacro log_error(error, log_level \\ :error, metadata \\ []) do
    quote bind_quoted: [error: error, log_level: log_level, metadata: metadata] do
      log_error_raw(nil, :error, error, log_level, metadata)
    end
  end

  @doc """
  Like `log_error/3`, but also puts the given`message` before the formatted error.
  """
  defmacro log_message_and_error(message, error, log_level \\ :error, metadata \\ []) do
    quote bind_quoted: [message: message, error: error, log_level: log_level, metadata: metadata] do
      log_error_raw(message, :error, error, log_level, metadata)
    end
  end

  @doc """
  Like `log_error/3`, but is used to log caught exits.

  When the pid is given, it will pass `{:EXIT, pid}` instead of `:exit` to `Exception.format/3`.
  """
  defmacro log_exit(error, pid \\ nil, log_level \\ :error, metadata \\ [])
  defmacro log_exit(error, nil, log_level, metadata) do
    quote bind_quoted: [error: error, log_level: log_level, metadata: metadata] do
      log_error_raw(nil, :exit, error, log_level, metadata)
    end
  end
  defmacro log_exit(error, pid, log_level, metadata) do
    quote bind_quoted: [error: error, log_level: log_level, metadata: metadata, pid: pid] do
      log_error_raw(nil, {:EXIT, pid}, error, log_level, metadata)
    end
  end
  @doc """
  Formats and logs the given `error` of the given `kind` with an optional preceding `message`.
  """
  defmacro log_error_raw(message, kind, error, log_level \\ :error, metadata \\ []) do
    quote do
      unquote(error)
      |> unquote(__MODULE__).format_error(unquote(kind))
      |> unquote(__MODULE__).log_formatted(unquote(message), unquote(log_level), unquote(metadata))
    end
  end

  @doc """
  Formats the given error using `Exception.format/3`.

  Adds the current stack trace, if available.
  """
  defmacro format_error(error, kind) do
    if in_catch?(__CALLER__) do
      quote do
        Exception.format(unquote(kind), unquote(error), __STACKTRACE__)
      end
    else
      quote do
        Exception.format(unquote(kind), unquote(error))
      end
    end
  end

  @doc """
  Logs a formatted error with an optional preceding message.
  """
  @spec log_formatted(binary, message, level :: Logger.level, metadata :: Logger.metadata) :: no_return
  def log_formatted(formatted, message, level \\ :error, metadata \\ []) do
    log_message =
      [message, formatted]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    Logger.log(level, log_message, metadata)
  end

  @doc """
  Returns if the environment is within a catch or rescue clause.

  Use it like this in a macro:

      defmacro maybe_get_stacktrace() do
        if in_catch?(__CALLER__) do
          quote do __STACKTRACE__ end
        else
          quote do [] end
        end
      end
  """
  @spec in_catch?(Macro.Env.t) :: boolean
  def in_catch?(env) do
    env
    |> Map.get(:contextual_vars, [])
    |> Enum.member?(:__STACKTRACE__)
  end
end
