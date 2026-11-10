defmodule CourierWeb.UserLive.SettingsTest do
  use CourierWeb.ConnCase, async: true

  alias Courier.Core.Accounts
  import Phoenix.LiveViewTest
  import Courier.Core.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/settings")

      assert html =~ "Trocar e-mail"
      assert html =~ "Trocar senha"
    end

    test "offers to set a password to an account without one", %{conn: conn} do
      {:ok, user} = Accounts.get_or_register_user_from_google(%{email: unique_user_email()})
      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/settings")

      assert html =~ "Definir senha"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/settings")
      assert path == ~p"/login"
      assert %{"error" => "Entre para acessar esta página."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      assert {:error, {:redirect, %{to: path, flash: flash}}} =
               conn
               |> log_in_user(user_fixture(),
                 token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
               )
               |> live(~p"/settings")

      assert path == ~p"/login?#{[return_to: ~p"/settings"]}"
      assert %{"error" => "Por segurança, entre de novo para continuar."} = flash
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "sends the confirmation to the new email", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      result =
        lv
        |> form("#email_form", %{"user" => %{"email" => unique_user_email()}})
        |> render_submit()

      assert result =~ "Enviamos um link de confirmação"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{"user" => %{"email" => "with spaces"}})

      assert result =~ "precisa ter o @ e não pode ter espaços"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = "new valid password"
      {:ok, lv, _html} = live(conn, ~p"/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)
      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/settings"
      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Senha alterada"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{"password" => "short", "password_confirmation" => "does not match"}
        })

      assert result =~ "deve ter entre 8 e 72 caracteres"
      assert result =~ "não confere com a senha"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/settings"
      assert %{"info" => "E-mail alterado com sucesso."} = flash
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      {:error, redirect} = live(conn, ~p"/settings/confirm-email/#{token}")
      assert {:live_redirect, %{flash: flash}} = redirect
      assert %{"error" => "O link de troca de e-mail é inválido ou expirou."} = flash
    end
  end
end
