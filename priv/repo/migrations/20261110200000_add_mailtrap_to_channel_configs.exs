defmodule Courier.Repo.Migrations.AddMailtrapToChannelConfigs do
  use Ecto.Migration

  def change do
    alter table(:channel_configs) do
      add :mailtrap_inbox_id, :string
    end
  end
end
