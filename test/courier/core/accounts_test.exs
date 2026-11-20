defmodule Courier.Core.AccountsTest do
  use Courier.DataCase

  alias Courier.Core.Accounts

  import Courier.Core.AccountsFixtures
  alias Courier.Core.Accounts.User

  describe "get_user_from_google/1" do
    test "does not create an account for an unknown email" do
      email = unique_user_email()
      assert {:error, :not_found} = Accounts.get_user_from_google(%{email: email})
      refute Accounts.get_user_by_email(email)
    end

    test "returns an existing confirmed user untouched" do
      %{id: id, confirmed_at: confirmed_at} = user = user_fixture()

      assert {:ok, %User{id: ^id, confirmed_at: ^confirmed_at}} =
               Accounts.get_user_from_google(%{email: user.email})
    end

    test "confirms an unconfirmed user" do
      user = unconfirmed_user_fixture()

      assert {:ok, claimed} = Accounts.get_user_from_google(%{email: user.email})
      assert claimed.id == user.id
      assert claimed.confirmed_at
    end
  end

  describe "ensure_admin/1" do
    test "creates a confirmed admin" do
      assert {:created, user} = Accounts.ensure_admin("admin@exemplo.com.br")
      assert user.email == "admin@exemplo.com.br"
      assert user.confirmed_at
    end

    test "keeps an existing account" do
      %{id: id} = user = user_fixture()
      assert {:existing, %User{id: ^id}} = Accounts.ensure_admin(user.email)
    end
  end

  describe "User.email_changeset/2" do
    test "validates format and uniqueness" do
      changeset = User.email_changeset(%User{}, %{email: "sem arroba"})
      assert "precisa ter o @ e não pode ter espaços" in errors_on(changeset).email

      user = user_fixture()
      changeset = User.email_changeset(%User{}, %{email: user.email})
      assert "já está em uso" in errors_on(changeset).email
    end
  end

  describe "session tokens" do
    test "generates, finds and deletes a session token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {session_user, _inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id

      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end
end
