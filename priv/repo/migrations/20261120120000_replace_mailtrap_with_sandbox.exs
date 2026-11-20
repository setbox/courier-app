defmodule Courier.Repo.Migrations.ReplaceMailtrapWithSandbox do
  use Ecto.Migration

  def up do
    execute """
    UPDATE channel_configs
    SET provider = 'sandbox', server_token = NULL, server_token_hint = NULL
    WHERE provider = 'mailtrap_sandbox'
    """

    alter table(:channel_configs) do
      remove :mailtrap_inbox_id
    end
  end

  def down do
    alter table(:channel_configs) do
      add :mailtrap_inbox_id, :string
    end
  end
end
