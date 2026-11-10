defmodule Courier.Repo.Migrations.CreateMessaging do
  use Ecto.Migration

  def change do
    create table(:apps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:apps, [:slug])

    create table(:environments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :app_id, references(:apps, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :client_token_hash, :binary
      add :client_token_hint, :string
      add :client_token_generated_at, :utc_datetime
      add :webhook_url, :string
      add :webhook_secret, :binary

      timestamps(type: :utc_datetime)
    end

    create unique_index(:environments, [:app_id, :slug])
    create unique_index(:environments, [:client_token_hash])

    create table(:channel_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :environment_id, references(:environments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :channel, :string, null: false
      add :provider, :string, null: false
      add :server_token, :binary
      add :server_token_hint, :string
      add :from_email, :string
      add :from_name, :string
      add :message_stream, :string, null: false, default: "outbound"
      add :track_opens, :boolean, null: false, default: false
      add :track_links, :boolean, null: false, default: false
      add :inbound_password, :binary
      add :postmark_webhook_id, :bigint
      add :postmark_webhook_error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channel_configs, [:environment_id, :channel])

    create table(:emails, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :environment_id, references(:environments, type: :binary_id, on_delete: :restrict),
        null: false

      add :status, :string, null: false
      add :from, :string, null: false
      add :subject, :text, null: false
      add :reply_to, :string
      add :tag, :string
      add :message_stream, :string
      add :metadata, :map, null: false, default: %{}
      add :idempotency_key, :string
      add :track_opens, :boolean, null: false, default: false
      add :track_links, :boolean, null: false, default: false
      add :body_key, :string, null: false
      add :provider_message_id, :string
      add :error_code, :integer
      add :error_message, :text
      add :attempts, :integer, null: false, default: 0
      add :sent_at, :utc_datetime
      add :failed_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    create index(:emails, [:environment_id, :inserted_at, :id])
    create index(:emails, [:environment_id, :idempotency_key])
    create index(:emails, [:provider_message_id])
    create index(:emails, [:inserted_at])
    create index(:emails, [:metadata], using: :gin)

    create table(:email_recipients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email_id, references(:emails, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :address, :citext, null: false
      add :status, :string, null: false, default: "pending"
      add :status_at, :utc_datetime
      add :detail, :text
      add :opened_at, :utc_datetime
      add :clicked_at, :utc_datetime
    end

    create index(:email_recipients, [:email_id])
    create index(:email_recipients, [:address])

    create table(:email_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email_id, references(:emails, type: :binary_id, on_delete: :delete_all), null: false

      add :recipient_id,
          references(:email_recipients, type: :binary_id, on_delete: :nilify_all)

      add :type, :string, null: false
      add :occurred_at, :utc_datetime, null: false
      add :data, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:email_events, [:email_id, :occurred_at])

    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :email_event_id, references(:email_events, type: :binary_id, on_delete: :delete_all),
        null: false

      add :url, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :response_status, :integer
      add :response_error, :text
      add :last_attempt_at, :utc_datetime
      add :delivered_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:webhook_deliveries, [:email_event_id])
  end
end
