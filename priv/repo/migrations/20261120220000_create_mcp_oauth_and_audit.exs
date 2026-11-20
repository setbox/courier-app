defmodule Courier.Repo.Migrations.CreateMcpOauthAndAudit do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :name, :string
      add :last_used_at, :utc_datetime
    end

    create table(:oauth_clients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :redirect_uris, {:array, :text}, null: false
      add :token_endpoint_auth_method, :string, null: false
      add :secret_hash, :binary

      timestamps(type: :utc_datetime)
    end

    create table(:oauth_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code_hash, :binary, null: false

      add :client_id, references(:oauth_clients, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :redirect_uri, :text, null: false
      add :code_challenge, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:oauth_codes, [:code_hash])
    create index(:oauth_codes, [:client_id])
    create index(:oauth_codes, [:user_id])

    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :actor_email, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_logs, [:inserted_at])
    create index(:audit_logs, [:action])
  end
end
