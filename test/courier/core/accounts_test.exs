defmodule Courier.Core.AccountsTest do
  use Courier.DataCase

  alias Courier.Core.Accounts

  import Courier.Core.AccountsFixtures
  alias Courier.Core.Accounts.{User, UserToken}

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "does not return a user without password" do
      user = passwordless_user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "")
    end
  end

  describe "register_user/1" do
    test "requires email and password" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["não pode ficar em branco"], password: ["não pode ficar em branco"]} =
               errors_on(changeset)
    end

    test "validates email and password format" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid", password: "short"})

      assert %{
               email: ["precisa ter o @ e não pode ter espaços"],
               password: ["deve ter entre 8 e 72 caracteres"]
             } = errors_on(changeset)
    end

    test "validates email uniqueness ignoring case" do
      %{email: email} = user_fixture()

      {:error, changeset} =
        Accounts.register_user(%{email: String.upcase(email), password: valid_user_password()})

      assert "já está em uso" in errors_on(changeset).email
    end

    test "registers an unconfirmed user with hashed password" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))

      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "confirm_user/1" do
    test "confirms the user with a valid token and spends it" do
      user = unconfirmed_user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      assert {:ok, confirmed} = Accounts.confirm_user(token)
      assert confirmed.confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id, context: "confirm")
      assert Accounts.confirm_user(token) == :error
    end

    test "does not confirm with an invalid token" do
      assert Accounts.confirm_user("oops") == :error
    end

    test "does not send instructions to a confirmed user" do
      user = user_fixture()

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(user, & &1)
    end
  end

  describe "reset password" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "finds the user by token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      refute Accounts.get_user_by_reset_password_token("oops")
    end

    test "does not find the user after a day", %{token: token} do
      Repo.update_all(UserToken,
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -2, :day)]
      )

      refute Accounts.get_user_by_reset_password_token(token)
    end

    test "resets the password and deletes all tokens", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_user, _expired}} =
        Accounts.reset_user_password(user, %{
          password: "new valid password",
          password_confirmation: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "validates the confirmation", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "new valid password",
          password_confirmation: "another"
        })

      assert %{password_confirmation: ["não confere com a senha"]} = errors_on(changeset)
    end
  end

  describe "get_user_from_google/1" do
    test "does not create an account for an unknown email" do
      email = unique_user_email()
      assert {:error, :not_found} = Accounts.get_user_from_google(%{email: email})
      refute Accounts.get_user_by_email(email)
    end

    test "returns an existing confirmed user untouched" do
      %{id: id, hashed_password: hash} = user = user_fixture()

      assert {:ok, %User{id: ^id, hashed_password: ^hash}} =
               Accounts.get_user_from_google(%{email: user.email})
    end

    test "claims an unconfirmed user dropping password and tokens" do
      user = unconfirmed_user_fixture()
      _ = Accounts.generate_user_session_token(user)

      assert {:ok, claimed} = Accounts.get_user_from_google(%{email: user.email})
      assert claimed.confirmed_at
      assert is_nil(claimed.hashed_password)
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "ensure_admin/2" do
    test "creates a confirmed admin with the given password" do
      assert {:created, user, "root@Setbox"} =
               Accounts.ensure_admin("admin@example.com", "root@Setbox")

      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password("admin@example.com", "root@Setbox")
    end

    test "generates a password when none is given" do
      assert {:created, _user, password} = Accounts.ensure_admin("admin@example.com", nil)
      assert Accounts.get_user_by_email_and_password("admin@example.com", password)
    end

    test "keeps an existing password" do
      user = user_fixture()
      assert {:existing, _} = Accounts.ensure_admin(user.email, "other password")
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "sets the password of an account without one" do
      user = passwordless_user_fixture()
      assert {:password_set, _, "root@Setbox"} = Accounts.ensure_admin(user.email, "root@Setbox")
      assert Accounts.get_user_by_email_and_password(user.email, "root@Setbox")
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update the email with an invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == {:error, :transaction_aborted}
    end
  end

  describe "update_user_password/2" do
    test "updates the password and deletes all tokens" do
      user = user_fixture()
      _ = Accounts.generate_user_session_token(user)

      {:ok, {user, expired}} =
        Accounts.update_user_password(user, %{password: "new valid password"})

      assert length(expired) == 1
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
      refute Repo.get_by(UserToken, user_id: user.id)
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

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
