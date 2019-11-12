defmodule Andi.Migration.MigrationsTest do
  use ExUnit.Case
  use Placebo

  import Andi, only: [instance_name: 0]

  @instance Andi.instance_name()

  alias Andi.Migration.Migrations

  test "send the modified date migration event if it has not succeeded yet" do
    allow(Brook.get!(@instance, :migration, "modified_date_migration_completed"), return: nil)
    allow(Brook.Event.send(any(), any(), any(), any()), return: :ok)

    Migrations.migrate_modified_dates()

    assert_called Brook.Event.send(@instance, "migration:modified_dates", :andi, %{})
  end

  test "Do not send the modified date migration event if it already succeeded" do
    allow(Brook.get!(@instance, any(), any()), return: true)
    allow(Brook.Event.send(any(), any(), any(), any()), return: :ok)

    Migrations.migrate_modified_dates()

    refute_called Brook.get_all_values!(@instance, :dataset)
    refute_called Brook.Event.send(@instance, any(), any(), any())
  end
end