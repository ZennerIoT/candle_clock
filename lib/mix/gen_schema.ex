defmodule Mix.Tasks.CandleClock.Gen.Schema do
  alias CandleClock.MixTasks.Utils

  require EEx
  template_file = Path.join([__DIR__, "./templates/schema.ex.eex"])
  EEx.function_from_file(:defp, :render_schema, template_file, [:assigns])

  def run(params) do
    {opts, [filename], _} = OptionParser.parse(params, strict: [overwrite: :boolean])

    assigns = %{
      schema_name: "CandleClock.Timer",
      table_name: "candle_clock_timers",
      datetime_type: ":utc_datetime"
    }

    code = render_schema(assigns)

    Utils.write(filename, code, opts)
  end

  for var <- [:schema_name, :table_name, :datetime_type] do
    defp unquote(var)(params) do
      Map.get(params, unquote(var))
    end
  end
end
