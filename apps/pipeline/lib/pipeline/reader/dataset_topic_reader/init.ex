defmodule Pipeline.Reader.DatasetTopicReader.InitTask do
  @moduledoc false

  use GenServer, restart: :transient
  use Retry

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    config = parse_args(args)

    Elsa.create_topic(config.endpoints, config.topic)
    wait_for_topic!(config)

    {:ok, config, {:continue, :start_consumer}}
  end

  def handle_continue(:start_consumer, config) do
    consumer = consumer_spec(config)

    case DynamicSupervisor.start_child(Pipeline.DynamicSupervisor, consumer) do
      {:ok, pid} ->
        Registry.put_meta(Pipeline.Registry, config.connection, pid)
        {:stop, :normal, config}

      {:error, {:already_started, _}} ->
        {:stop, :normal, config}

      {:error, {_, {_, _, {:already_started, _}}}} ->
        {:stop, :normal, config}

      error ->
        {:stop, "Failed to supervise #{config.topic} consumer: #{inspect(error)}", config}
    end
  end

  defp parse_args(args) do
    instance = Keyword.fetch!(args, :instance)
    dataset = Keyword.fetch!(args, :dataset)
    topic = "#{Keyword.fetch!(args, :input_topic_prefix)}-#{dataset.id}"

    %{
      instance: instance,
      endpoints: Keyword.fetch!(args, :endpoints),
      dataset: dataset,
      handler: Keyword.fetch!(args, :handler),
      topic: topic,
      retry_count: Keyword.get(args, :retry_count, 10),
      retry_delay: Keyword.get(args, :retry_delay, 100),
      topic_subscriber_config: Keyword.get(args, :topic_subscriber_config, []),
      connection: :"#{instance}-#{topic}-consumer"
    }
  end

  defp consumer_spec(config) do
    start_options = [
      endpoints: config.endpoints,
      connection: config.connection,
      group_consumer: [
        group: "#{config.instance}-#{config.topic}",
        topics: [config.topic],
        handler: config.handler,
        handler_init_args: [dataset: config.dataset],
        config: config.topic_subscriber_config
      ]
    ]

    {Elsa.Supervisor, start_options}
  end

  defp wait_for_topic!(config) do
    wait exponential_backoff(config.retry_delay) |> Stream.take(config.retry_count) do
      Elsa.topic?(config.endpoints, config.topic)
    after
      _ -> config.topic
    else
      _ -> raise "Timed out waiting for #{config.topic} to be available"
    end
  end
end
