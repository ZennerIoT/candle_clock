defmodule CandleClock.ErlangTermType do
  @moduledoc false
  use Ecto.Type

  def type, do: :binary

  def cast(term), do: {:ok, term}
  def load(binary), do: {:ok, :erlang.binary_to_term(binary)}
  def dump(term), do: {:ok, :erlang.term_to_binary(term)}
end
