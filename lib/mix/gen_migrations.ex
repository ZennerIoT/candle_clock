defmodule Mix.Tasks.CandleClock.Gen.Migrations do
  use Mix.Task

  alias CandleClock.MixTasks.Utils

  require EEx
  migrations = "./templates/migrations/"

  @migrations Path.join([__DIR__, migrations])
              |> File.ls!()
              |> Enum.map(fn file ->
                %{
                  source: Path.join([__DIR__, migrations, file]),
                  target: "priv/repo/migrations/" <> String.replace_trailing(file, ".eex", ""),
                  fun_name:
                    ("render_migration_" <> String.replace_trailing(file, ".exs.eex", ""))
                    |> String.to_atom()
                }
              end)

  for migration <- @migrations do
    EEx.function_from_file(:def, migration.fun_name, migration.source, [:assigns])
  end

  def run(params) do
    {opts, _, _} = OptionParser.parse(params, strict: [overwrite: :boolean])

    assigns = %{
      module_prefix: "CandleClock.Migrations",
      table_name: "candle_clock_timers",
      db_datetime_type: ~S[:"timestamp with time zone"]
    }

    create_migrations(assigns, opts)
  end

  def create_migrations(assigns, options) do
    File.mkdir_p!("priv/repo/migrations")

    for migration <- @migrations do
      code = apply(__MODULE__, migration.fun_name, [assigns])
      Utils.write(migration.target, code, options)
    end
  end

  for var <- [:module_prefix, :table_name, :db_datetime_type] do
    defp unquote(var)(params) do
      Map.get(params, unquote(var))
    end
  end
end
