defmodule Courier.Repo.Migrations.AddWebhookEventsToEnvironments do
  use Ecto.Migration

  def up do
    alter table(:environments) do
      add :webhook_events, {:array, :string}, null: false, default: []
    end

    execute """
    UPDATE environments
    SET webhook_events = ARRAY['sent', 'failed', 'delivery', 'not_found', 'bounce', 'spam_complaint', 'open', 'click', 'subscription_change']
    WHERE webhook_url IS NOT NULL
    """
  end

  def down do
    alter table(:environments) do
      remove :webhook_events
    end
  end
end
