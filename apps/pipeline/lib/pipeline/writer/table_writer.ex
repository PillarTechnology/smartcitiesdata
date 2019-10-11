defmodule Pipeline.Writer.TableWriter do
  @moduledoc """
  Implementation of `Pipeline.Writer` for PrestoDB tables.
  """

  @behaviour Pipeline.Writer
  alias Pipeline.Writer.TableWriter.Compaction
  alias Pipeline.Presto
  require Logger

  @type schema() :: [map()]

  @impl Pipeline.Writer
  @spec init(table: String.t(), schema: schema()) :: :ok | {:error, term()}
  @doc """
  Ensures PrestoDB table exists.
  """
  def init(args) do
    config = parse_args(args)

    with {:ok, statement} <- Presto.create(config),
         [[true]] <- execute(statement) do
      Logger.info("Created #{config.table} table")
      :ok
    else
      error ->
        Logger.error("Error creating #{config.table} table: #{inspect(error)}")
        {:error, "Write to Presto failed: #{inspect(error)}"}
    end
  end

  @impl Pipeline.Writer
  @spec write([term()], table: String.t(), schema: schema()) :: :ok | {:error, term()}
  @doc """
  Writes data to PrestoDB table.
  """
  def write([], config) do
    table = Keyword.fetch!(config, :table)
    Logger.debug("No data to write to #{table}")
    :ok
  end

  def write(content, config) do
    payloads = Enum.map(content, &Map.get(&1, :payload))

    parse_args(config)
    |> Presto.insert(payloads)
    |> execute()
    |> case do
      [[_]] -> :ok
      error -> {:error, error}
    end
  end

  @impl Pipeline.Writer
  @spec compact(table: String.t()) :: :ok | {:error, term()}
  @doc """
  Creates a new, compacted table from a table. Compaction reduces the number
  of ORC files stored by object storage.
  """
  def compact(args) do
    table = Keyword.fetch!(args, :table)

    Compaction.setup(table)
    |> Compaction.run()
    |> Compaction.measure(table)
    |> Compaction.complete(table)
  end

  defp parse_args(args) do
    %{
      table: Keyword.fetch!(args, :table),
      schema: Keyword.fetch!(args, :schema)
    }
  end

  defp execute(statement) do
    statement
    |> Prestige.execute()
    |> Prestige.prefetch()
  end
end
