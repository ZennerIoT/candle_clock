defmodule CandleClock.CronTabType do
  use Ecto.Type

  def type, do: :string
  def cast(bin), do: {:ok, bin}
  def load(bin), do: {:ok, bin}
  def dump(bin), do: {:ok, bin}
end
