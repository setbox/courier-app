defmodule Courier.Repo.Migrations.AddBrevoToChannelConfigs do
  use Ecto.Migration

  def change do
    alter table(:channel_configs) do
      add :brevo_webhook_id, :bigint
      add :brevo_webhook_error, :text
    end
  end
end
