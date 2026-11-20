defmodule Courier.Core.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email], message: "não pode ficar em branco")
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "precisa ter o @ e não pode ter espaços"
    )
    |> validate_length(:email, max: 160, message: "deve ter no máximo 160 caracteres")
    |> unsafe_validate_unique(:email, Courier.Repo, message: "já está em uso")
    |> unique_constraint(:email, message: "já está em uso")
  end

  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now(:second))
  end
end
