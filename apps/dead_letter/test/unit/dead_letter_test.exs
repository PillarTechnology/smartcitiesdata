defmodule DeadLetterTest do
  use ExUnit.Case
  use Placebo
  import Assertions
  alias DeadLetter.Carrier.Test, as: Carrier

  @default_stacktrace [
    {:erlang, :/, [1, 0], []},
    {DeadLetter, :catcher, 1, [file: 'lib/dead_letter.ex', line: 26]},
    {:erl_eval, :do_apply, 6, [file: 'erl_eval.erl', line: 680]},
    {:elixir, :eval_forms, 4, [file: 'src/elixir.erl', line: 258]},
    {IEx.Evaluator, :handle_eval, 5, [file: 'lib/iex/evaluator.ex', line: 257]},
    {IEx.Evaluator, :do_eval, 3, [file: 'lib/iex/evaluator.ex', line: 237]},
    {IEx.Evaluator, :eval, 3, [file: 'lib/iex/evaluator.ex', line: 215]},
    {IEx.Evaluator, :loop, 1, [file: 'lib/iex/evaluator.ex', line: 103]}
  ]

  @default_original_message %{
    payload: "{}",
    topic: "streaming-raw"
  }

  @dataset_id "ds1"

  setup do
    config = [driver: [module: DeadLetter.Carrier.Test, init_args: [size: 3_000]]]

    {:ok, dlq} = DeadLetter.start_link(config)

    on_exit(fn ->
      ref = Process.monitor(dlq)
      Process.exit(dlq, :normal)
      assert_receive {:DOWN, ^ref, _, _, _}
    end)
  end

  describe "process/2" do
    @tag capture_log: true
    test "sends formatted message to the queue" do
      DeadLetter.process(@dataset_id, @default_original_message, "forklift")

      assert_async do
        expected = %{
          dataset_id: @dataset_id,
          app: "forklift",
          original_message: @default_original_message
        }

        {:ok, actual} = Carrier.receive()

        refute actual == :empty

        comparison =
          &(&1.dataset_id == &2.dataset_id and &1.app == &2.app and &1.original_message == &2.original_message)

        assert_maps_equal(expected, actual, comparison)
      end
    end

    @tag capture_log: true
    test "message is an unparseable binary" do
      message = <<80, 75, 3, 4, 20, 0, 6, 0, 8, 0, 0, 0, 33, 0, 235, 122, 210>>

      DeadLetter.process(@dataset_id, message, "forklift")

      assert_async do
        {:ok, actual} = Carrier.receive()
        refute actual == :empty
        assert actual.original_message == "<<80, 75, 3, 4, 20, 0, 6, 0, 8, 0, 0, 0, 33, 0, 235, 122, 210>>"
      end
    end

    test "properly handles tuples being passed" do
      DeadLetter.process(@dataset_id, "some message", "valkyrie", reason: {:error, "bad date!"})

      assert_async do
        {:ok, actual} = Carrier.receive()
        refute actual == :empty
        assert actual.reason == {:error, "bad date!"}
      end
    end
  end

  describe "format_message/2" do
    test "returns formatted DLQ message with defaults and empty original message" do
      actual = DeadLetter.Server.format_message(@default_original_message, @dataset_id, "forklift")

      assert match?(
               %{
                 app: "forklift",
                 original_message: %{},
                 exit_code: nil,
                 error: nil,
                 reason: nil,
                 timestamp: %DateTime{}
               },
               actual
             )

      assert Map.get(actual, :stacktrace) =~ "DeadLetter.Server.format_message"
    end

    test "returns formatted DLQ message with defaults and non-empty original message" do
      actual = DeadLetter.Server.format_message(@default_original_message, @dataset_id, "forklift")

      assert Map.get(actual, :original_message) == %{payload: "{}", topic: "streaming-raw"}
    end

    test "returns formatted DLQ message with a reason" do
      actual =
        DeadLetter.Server.format_message("forklift", @dataset_id, @default_original_message,
          reason: "Failed to parse something"
        )

      assert "Failed to parse something" == Map.get(actual, :reason)
    end

    test "returns formatted DLQ message with a reason exception" do
      actual =
        DeadLetter.Server.format_message("forklift", @dataset_id, @default_original_message,
          reason: RuntimeError.exception("Failed to parse something")
        )

      assert "** (RuntimeError) Failed to parse something" == Map.get(actual, :reason)
    end

    test "returns formatted DLQ message with an error" do
      actual =
        DeadLetter.Server.format_message("forklift", @dataset_id, @default_original_message,
          error: "Failed to parse something"
        )

      assert "Failed to parse something" == Map.get(actual, :error)
    end

    test "returns formatted DLQ message with an error exception" do
      actual =
        DeadLetter.Server.format_message("forklift", @dataset_id, @default_original_message,
          error: KeyError.exception("Bad Key!")
        )

      assert "** (KeyError) Bad Key!" == Map.get(actual, :error)
    end

    test "returns formatted DLQ message with a stacktrace from Process.info" do
      stacktrace = {:current_stacktrace, @default_stacktrace}

      actual =
        DeadLetter.Server.format_message(@default_original_message, @dataset_id, "forklift", stacktrace: stacktrace)

      assert Map.get(actual, :stacktrace) == Exception.format_stacktrace(@default_stacktrace)
    end

    test "returns formatted DLQ message with a stacktrace from System.stacktrace" do
      actual =
        DeadLetter.Server.format_message(@default_original_message, @dataset_id, "forklift",
          stacktrace: @default_stacktrace
        )

      assert Map.get(actual, :stacktrace) == Exception.format_stacktrace(@default_stacktrace)
    end

    test "returns formatted DLQ message with an exit" do
      an_exit =
        try do
          raise "Error"
        rescue
          e -> e
        end

      actual = DeadLetter.Server.format_message("forklift", @dataset_id, @default_original_message, exit_code: an_exit)

      assert "%RuntimeError{message: \"Error\"}" == Map.get(actual, :exit_code)
    end

    test "sets the timestamp on DLQ message" do
      actual = DeadLetter.Server.format_message("forklift", @dataset_id, @default_original_message)

      assert %DateTime{} = Map.get(actual, :timestamp)
    end

    test "allows overriding the timestamp on DLQ message" do
      epoch = DateTime.from_unix!(0)

      actual = DeadLetter.Server.format_message("forklift", @dataset_id, @default_original_message, timestamp: epoch)

      assert epoch == Map.get(actual, :timestamp)
    end
  end
end
