defmodule CandleClock.MixTasks.Utils do
  def write(filename, code, opts) do
    if not File.exists?(filename) or Keyword.get(opts, :overwrite, false) do
      File.write!(filename, code)

      IO.puts([
        IO.ANSI.green(),
        " * Generated ",
        IO.ANSI.reset(),
        filename
      ])
    else
      IO.puts([
        IO.ANSI.red(),
        " * Failed to generate ",
        IO.ANSI.reset(),
        filename,
        IO.ANSI.red(),
        " - this file already exists. Pass ",
        IO.ANSI.reset(),
        "--overwrite",
        IO.ANSI.red(),
        " to generate this file anyway.",
        IO.ANSI.reset()
      ])
    end
  end
end
