alias CandleClock, as: CC
CC.Repo.start_link()
CC.Worker.start_link()

defmodule Util do
  def mfa(word \\ "Hello") do
    {IO, :puts, [word]}
  end
end
