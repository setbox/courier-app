defmodule Courier.Repo.Migrations.AddCategoryAndDailyStats do
  use Ecto.Migration

  def up do
    alter table(:emails) do
      add :category, :string, null: false, default: "transactional"
      add :provider, :string
    end

    execute """
    UPDATE emails AS e
    SET provider = c.provider
    FROM channel_configs AS c
    WHERE c.environment_id = e.environment_id AND c.channel = 'email' AND e.status <> 'queued'
    """

    alter table(:emails) do
      modify :category, :string, null: false, default: nil
    end

    alter table(:email_recipients) do
      add :bounce_kind, :string
    end

    create index(:emails, [:sent_at])
    create index(:emails, [:failed_at])
    create index(:email_recipients, [:status, :status_at])

    create table(:email_daily_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :day, :date, null: false

      add :environment_id, references(:environments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :provider, :string, null: false
      add :category, :string, null: false
      add :sent, :integer, null: false, default: 0
      add :delivered, :integer, null: false, default: 0
      add :failed, :integer, null: false, default: 0
      add :not_found, :integer, null: false, default: 0
      add :bounced, :integer, null: false, default: 0
      add :spam, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:email_daily_stats, [:day, :environment_id, :provider, :category])
  end

  def down do
    drop table(:email_daily_stats)
    drop index(:email_recipients, [:status, :status_at])
    drop index(:emails, [:failed_at])
    drop index(:emails, [:sent_at])

    alter table(:email_recipients) do
      remove :bounce_kind
    end

    alter table(:emails) do
      remove :provider
      remove :category
    end
  end
end
