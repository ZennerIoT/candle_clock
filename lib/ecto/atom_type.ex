defmodule CandleClock.AtomType do
  use Ecto.Type

  def type, do: :string

  def load(binary) do
    {:ok, String.to_atom(binary)}
  end

  def cast(binary) when is_binary(binary) do
    load(binary)
  end

  def cast(module) when is_atom(module) do
    {:ok, module}
  end

  def dump(module) do
    {:ok, to_string(module)}
  end
end
