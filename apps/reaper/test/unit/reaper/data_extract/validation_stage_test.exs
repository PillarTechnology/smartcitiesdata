defmodule Reaper.DataExtract.ValidationStageTest do
  use ExUnit.Case
  use Placebo

  alias Reaper.DataExtract.ValidationStage
  alias Reaper.Cache
  alias SmartCity.TestDataGenerator, as: TDG

  @cache :validation_stage_test

  setup do
    {:ok, registry} = Horde.Registry.start_link(keys: :unique, name: Reaper.Cache.Registry)
    {:ok, horde_sup} = Horde.DynamicSupervisor.start_link(strategy: :one_for_one, name: Reaper.Horde.Supervisor)
    Horde.DynamicSupervisor.start_child(Reaper.Horde.Supervisor, {Reaper.Cache, name: @cache})

    on_exit(fn ->
      kill(horde_sup)
      kill(registry)
    end)

    :ok
  end

  describe "handle_events/3" do
    test "will remove duplicates" do
      Cache.cache(@cache, %{one: 1, two: 2})

      incoming_events = [
        {%{one: 1, two: 2}, 1},
        {%{three: 3, four: 4}, 2}
      ]

      state = %{
        cache: @cache,
        dataset: dataset(id: "ds1", allow_duplicates: false),
        last_processed_index: -1
      }

      {:noreply, outgoing_events, _new_state} = ValidationStage.handle_events(incoming_events, self(), state)
      assert outgoing_events == [{%{three: 3, four: 4}, 2}]
    end

    test "will allow duplicates if configured to do so" do
      Cache.cache(@cache, %{one: 1, two: 2})

      incoming_events = [
        {%{one: 1, two: 2}, 1},
        {%{three: 3, four: 4}, 2}
      ]

      state = %{
        cache: @cache,
        dataset: dataset(id: "ds1"),
        last_processed_index: -1
      }

      {:noreply, outgoing_events, _new_state} = ValidationStage.handle_events(incoming_events, self(), state)
      assert outgoing_events == [{%{one: 1, two: 2}, 1}, {%{three: 3, four: 4}, 2}]
    end

    test "will remove any events that have already been processed" do
      state = %{
        cache: @cache,
        dataset: dataset(id: "ds2"),
        last_processed_index: 5
      }

      incoming_events = [
        {%{one: 1, two: 2}, 4},
        {%{three: 3, four: 4}, 5},
        {%{five: 5, six: 6}, 6}
      ]

      {:noreply, outgoing_events, _new_state} = ValidationStage.handle_events(incoming_events, self(), state)
      assert outgoing_events == [{%{five: 5, six: 6}, 6}]
    end

    test "will yeet any errors marked during cache call" do
      allow Cache.mark_duplicates(@cache, %{three: 3, four: 4}), return: {:error, "bad stuff"}
      allow Cache.mark_duplicates(@cache, any()), exec: fn _, msg -> {:ok, msg} end
      allow Yeet.process_dead_letter(any(), any(), any(), any()), return: :ok

      state = %{
        cache: @cache,
        dataset: dataset(id: "ds2", allow_duplicates: false),
        last_processed_index: -1
      }

      incoming_events = [
        {%{one: 1, two: 2}, 1},
        {%{three: 3, four: 4}, 2}
      ]

      {:noreply, outgoing_events, _new_state} = ValidationStage.handle_events(incoming_events, self(), state)
      assert outgoing_events == [{%{one: 1, two: 2}, 1}]
      assert_called Yeet.process_dead_letter("ds2", {%{three: 3, four: 4}, 2}, "reaper", reason: "bad stuff")
    end
  end

  defp dataset(opts) do
    TDG.create_dataset(
      id: Keyword.get(opts, :id, "ds1"),
      technical: %{
        sourceType: Keyword.get(opts, :sourceType, "ingest"),
        allow_duplicates: Keyword.get(opts, :allow_duplicates, true)
      }
    )
  end

  defp kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :normal)
    assert_receive {:DOWN, ^ref, _, _, _}
  end
end
