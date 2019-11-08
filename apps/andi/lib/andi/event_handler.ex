defmodule Andi.EventHandler do
  @moduledoc "Event Handler for event stream"
  use Brook.Event.Handler
  require Logger
  alias SmartCity.{Dataset, Organization}
  import SmartCity.Event, only: [dataset_update: 0, organization_update: 0, user_organization_associate: 0]
  alias SmartCity.UserOrganizationAssociate

  def handle_event(%Brook.Event{type: dataset_update(), data: %Dataset{} = data}) do
    {:merge, :dataset, data.id, data}
  end

  def handle_event(%Brook.Event{type: organization_update(), data: %Organization{} = data}) do
    {:merge, :org, data.id, data}
  end

  def handle_event(%Brook.Event{
        type: user_organization_associate(),
        data: %UserOrganizationAssociate{user_id: user_id, org_id: org_id}
      }) do
    merge(:org_to_users, org_id, &add_to_set(&1, user_id))
    merge(:user_to_orgs, user_id, &add_to_set(&1, org_id))
  end

  def handle_event(%Brook.Event{type: "migration:modifiedDateTime"}) do
    Andi.Migration.ModifiedDateMigration.do_migration()
    :discard
  end

  defp add_to_set(nil, id), do: MapSet.new([id])
  defp add_to_set(set, id), do: MapSet.put(set, id)
end
