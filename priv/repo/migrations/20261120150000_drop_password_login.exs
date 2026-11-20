defmodule Courier.Repo.Migrations.DropPasswordLogin do
  use Ecto.Migration

  def up do
    execute "DELETE FROM users_tokens WHERE context <> 'session'"

    alter table(:users) do
      remove :hashed_password
    end
  end

  def down do
    alter table(:users) do
      add :hashed_password, :string
    end
  end
end
