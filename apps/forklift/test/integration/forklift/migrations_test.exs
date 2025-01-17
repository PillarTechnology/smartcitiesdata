defmodule Forklift.MigrationsTest do
  use ExUnit.Case
  use Divo, services: [:zookeeper, :kafka, :redis]

  alias Forklift.Datasets.DatasetSchema
  alias SmartCity.TestDataGenerator, as: TDG
  import Forklift
  import SmartCity.Event, only: [dataset_update: 0, data_ingest_start: 0]

  test "stuff gets migrated" do
    dataset = TDG.create_dataset(id: "ds1", technical: %{sourceType: "ingest"})

    events = [
      Brook.Event.new(type: dataset_update(), author: "testing", data: dataset, create_ts: 0),
      Brook.Event.new(type: data_ingest_start(), author: "testing", data: dataset, create_ts: 1)
    ]

    Enum.each(events, fn event ->
      Brook.Test.with_event(instance_name(), event, fn ->
        Brook.ViewState.merge(:datasets_to_process, dataset.id, DatasetSchema.from_dataset(dataset))
      end)
    end)

    {:ok, pid} = Forklift.Migrations.start_link([])

    assert dataset == Forklift.Datasets.get!(dataset.id)
    assert events == Forklift.Datasets.get_events!(dataset.id)
    assert [] == Brook.get_all_values!(instance_name(), :datasets_to_process)
    assert false == Process.alive?(pid)
  end
end
