defmodule Courier.Core.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  def google_registration_changeset(user, attrs) do
    user
    |> email_changeset(attrs)
    |> change(confirmed_at: DateTime.utc_now(:second))
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email], message: "não pode ficar em branco")
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "precisa ter o @ e não pode ter espaços"
      )
      |> validate_length(:email, max: 160, message: "deve ter no máximo 160 caracteres")

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Courier.Repo, message: "já está em uso")
      |> unique_constraint(:email, message: "já está em uso")
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "não mudou")
    else
      changeset
    end
  end

  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "não confere com a senha")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password], message: "não pode ficar em branco")
    |> validate_length(:password,
      min: 8,
      max: 72,
      message: "deve ter entre 8 e 72 caracteres"
    )
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes, message: "é longa demais")
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now(:second))
  end

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
