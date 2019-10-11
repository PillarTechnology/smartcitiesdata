defmodule Pipeline.Presto.Create do
  @moduledoc false

  alias Pipeline.Presto.FieldTypeError

  @field_type_map %{
    "boolean" => "boolean",
    "date" => "date",
    "double" => "double",
    "float" => "double",
    "integer" => "integer",
    "long" => "bigint",
    "json" => "varchar",
    "string" => "varchar",
    "timestamp" => "timestamp"
  }

  def compose(name, schema) do
    "CREATE TABLE IF NOT EXISTS #{name} (#{translate_columns(schema)})"
  end

  defp translate_columns(cols) do
    cols
    |> Enum.map(&translate_column/1)
    |> Enum.join(", ")
  end

  def translate_column(%{type: "map"} = col) do
    row_def = translate_columns(col.subSchema)
    ~s|"#{col.name}" row(#{row_def})|
  end

  def translate_column(%{type: "list", itemType: "map"} = col) do
    row_def = translate_columns(col.subSchema)
    ~s|"#{col.name}" array(row(#{row_def}))|
  end

  def translate_column(%{type: "list", itemType: type} = col) do
    array_def = translate(type)
    ~s|"#{col.name}" array(#{array_def})|
  end

  def translate_column(col) do
    ~s|"#{col.name}" #{translate(col.type)}|
  end

  defp translate("decimal"), do: "decimal"

  defp translate("decimal" <> precision = type) do
    case Regex.match?(~r|\(\d{1,2},\d{1,2}\)|, precision) do
      true -> type
      false -> raise FieldTypeError, message: "#{type} Type is not supported"
    end
  end

  defp translate(type) do
    @field_type_map
    |> Map.get(type)
    |> case do
      nil -> raise FieldTypeError, message: "#{type} Type is not supported"
      value -> value
    end
  end
end
