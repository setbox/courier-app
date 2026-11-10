defmodule Courier.Repo.Migrations.AddRecipientListsToEnvironments do
  use Ecto.Migration

  def change do
    alter table(:environments) do
      add :allowed_recipients, {:array, :string}, null: false, default: []
      add :blocked_recipients, {:array, :string}, null: false, default: []
    end
  end
end
