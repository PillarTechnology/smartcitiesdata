defmodule Pipeline.Reader.DatasetTopicReaderTest do
  use ExUnit.Case
  use Divo
  use Placebo

  alias Pipeline.Reader.DatasetTopicReader
  alias SmartCity.TestDataGenerator, as: TDG

  import SmartCity.TestHelper, only: [eventually: 1, eventually: 3]

  @prefix "input-prefix"
  @brokers Application.get_env(:pipeline, :elsa_brokers)

  setup_all do
    {:ok, pid} = Registry.start_link(keys: :unique, name: Pipeline.TestRegistry)

    on_exit(fn ->
      ref = Process.monitor(pid)
      Process.exit(pid, :shutdown)
      assert_receive {:DOWN, ^ref, _, _, _}
    end)
  end

  describe "init/1" do
    setup do
      on_exit(fn ->
        DynamicSupervisor.which_children(Pipeline.DynamicSupervisor)
        |> Enum.map(&elem(&1, 1))
        |> Enum.each(fn pid ->
          Process.monitor(pid)
          DynamicSupervisor.terminate_child(Pipeline.DynamicSupervisor, pid)
          assert_receive {:DOWN, _, _, ^pid, _}
        end)
      end)
    end

    test "ensures topic exists to read from" do
      dataset = TDG.create_dataset(%{id: "test"})

      args = [
        instance: :pipeline,
        endpoints: @brokers,
        dataset: dataset,
        handler: Pipeline.TestHandler,
        input_topic_prefix: @prefix,
        retry_count: 10,
        retry_delay: 1
      ]

      assert :ok = DatasetTopicReader.init(args)

      eventually(fn ->
        assert {"#{@prefix}-test", 1} in Elsa.Topic.list(@brokers)
      end)
    end

    test "sets reader up to pass messages to a handler" do
      dataset = TDG.create_dataset(%{id: "read"})
      message = TDG.create_data(%{})

      args = [
        instance: :pipeline,
        endpoints: @brokers,
        dataset: dataset,
        handler: Pipeline.TestHandler,
        input_topic_prefix: @prefix,
        retry_count: 10,
        retry_delay: 1,
        topic_subscriber_config: [
          begin_offset: :earliest,
          offset_reset_policy: :reset_to_earliest
        ]
      ]

      assert :ok = DatasetTopicReader.init(args)
      eventually(fn -> assert {"#{@prefix}-read", 1} in Elsa.Topic.list(@brokers) end)

      Application.put_env(:smart_city_test, :endpoint, @brokers)
      SmartCity.KafkaHelper.send_to_kafka(message, "#{@prefix}-read")

      eventually(
        fn ->
          assert {:ok, [%Elsa.Message{value: json, topic: "#{@prefix}-read"}]} =
                   Registry.meta(Pipeline.TestRegistry, :messages)

          assert Jason.decode!(json)["payload"]["my_float"] == message.payload["my_float"]
          assert Jason.decode!(json)["payload"]["my_string"] == message.payload["my_string"]
        end,
        5_000,
        5
      )
    end

    test "tracks reader infrastructure" do
      dataset = TDG.create_dataset(%{id: "tracking"})

      args = [
        instance: :pipeline,
        endpoints: @brokers,
        dataset: dataset,
        handler: Pipeline.TestHandler,
        input_topic_prefix: @prefix,
        retry_count: 10,
        retry_delay: 1
      ]

      assert :ok = DatasetTopicReader.init(args)

      eventually(fn ->
        assert [{:undefined, pid, _, _}] = DynamicSupervisor.which_children(Pipeline.DynamicSupervisor)
        assert {:ok, ^pid} = Registry.meta(Pipeline.Registry, :"pipeline-#{@prefix}-#{dataset.id}-consumer")
      end)
    end

    test "idempotently sets up reader infrastructure" do
      dataset = TDG.create_dataset(%{id: "idempotent"})

      args = [
        instance: :pipeline,
        endpoints: @brokers,
        dataset: dataset,
        handler: Pipeline.TestHandler,
        input_topic_prefix: @prefix,
        retry_count: 10,
        retry_delay: 1
      ]

      assert :ok = DatasetTopicReader.init(args)
      assert :ok = DatasetTopicReader.init(args)

      [{:undefined, pid1, _, _}, {:undefined, pid2, _, _}, {:undefined, _pid3, _, _}] =
        DynamicSupervisor.which_children(Pipeline.DynamicSupervisor)

      Process.monitor(pid1)
      Process.monitor(pid2)

      eventually(fn ->
        assert {"#{@prefix}-idempotent", 1} in Elsa.Topic.list(@brokers)
        assert_receive {:DOWN, _, _, ^pid1, _}, 1_000
        assert_receive {:DOWN, _, _, ^pid2, _}, 1_000
      end)
    end

    test "fails if it cannot connect to dataset topic" do
      allow Elsa.create_topic(any(), "#{@prefix}-unreachable"), return: :ignore, meck_options: [:passthrough]
      dataset = TDG.create_dataset(%{id: "unreachable"})

      args = [
        instance: :pipeline,
        endpoints: @brokers,
        dataset: dataset,
        handler: Pipeline.TestHandler,
        input_topic_prefix: @prefix,
        retry_count: 10,
        retry_delay: 1
      ]

      assert :ok = DatasetTopicReader.init(args)
      [{:undefined, pid, _, _}] = DynamicSupervisor.which_children(Pipeline.DynamicSupervisor)
      Process.monitor(pid)

      assert_receive {:DOWN, _, _, ^pid, {%RuntimeError{message: msg}, _}}, 5_000
      assert msg == "Timed out waiting for #{@prefix}-unreachable to be available"
      assert {"#{@prefix}-unreachable", 1} not in Elsa.Topic.list(@brokers)
    end
  end

  describe "terminate/1" do
    test "tears down reader infrastructure" do
      dataset = TDG.create_dataset(%{id: "teardown"})

      args = [
        instance: :pipeline,
        endpoints: @brokers,
        dataset: dataset,
        handler: Pipeline.TestHandler,
        input_topic_prefix: @prefix,
        retry_count: 10,
        retry_delay: 1
      ]

      assert :ok = DatasetTopicReader.init(args)

      eventually(
        fn ->
          assert [{:undefined, pid, _, _}] = DynamicSupervisor.which_children(Pipeline.DynamicSupervisor)
          assert {:ok, ^pid} = Registry.meta(Pipeline.Registry, :"pipeline-#{@prefix}-#{dataset.id}-consumer")
          Process.monitor(pid)
        end,
        3_000,
        5
      )

      {:ok, pid} = Registry.meta(Pipeline.Registry, :"pipeline-#{@prefix}-#{dataset.id}-consumer")
      DatasetTopicReader.terminate(dataset: dataset, input_topic_prefix: @prefix, instance: :pipeline)

      assert_receive {:DOWN, _, _, ^pid, :shutdown}, 3_000
    end
  end
end

defmodule Pipeline.TestHandler do
  use Elsa.Consumer.MessageHandler

  def init(_ \\ []) do
    {:ok, []}
  end

  def handle_messages(messages, state) do
    Registry.put_meta(Pipeline.TestRegistry, :messages, messages)
    {:ack, state}
  end
end
