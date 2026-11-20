defmodule Courier.Core.AccountsFixtures do
  import Ecto.Query

  alias Courier.Core.Accounts
  alias Courier.Core.Accounts.{Scope, User}

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def unconfirmed_user_fixture(attrs \\ %{}) do
    %User{}
    |> User.email_changeset(Enum.into(attrs, %{email: unique_user_email()}))
    |> Courier.Repo.insert!()
  end

  def user_fixture(attrs \\ %{}) do
    attrs
    |> unconfirmed_user_fixture()
    |> User.confirm_changeset()
    |> Courier.Repo.update!()
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Courier.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Courier.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
