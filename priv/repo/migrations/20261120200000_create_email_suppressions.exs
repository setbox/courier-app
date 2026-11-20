defmodule Courier.Repo.Migrations.CreateEmailSuppressions do
  use Ecto.Migration

  def change do
    create table(:email_suppressions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :environment_id, references(:environments, type: :binary_id, on_delete: :delete_all),
        null: false

      add :address, :string, null: false
      add :email_id, references(:emails, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:email_suppressions, [:environment_id, :address])
  end
end
