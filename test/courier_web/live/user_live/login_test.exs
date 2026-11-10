defmodule CourierWeb.UserLive.LoginTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.Core.AccountsFixtures

  describe "login page" do
    test "renders the page with the Google button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Entrar"
      assert html =~ "Esqueci minha senha"
      assert html =~ "Continuar com o Google"
    end
  end

  describe "password login" do
    test "logs the user in", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/login")

      form =
        form(lv, "#login_form",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects back to login with invalid credentials", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/login")

      form = form(lv, "#login_form", user: %{email: "test@email.com", password: "123456"})
      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "E-mail ou senha inválidos."
      assert redirected_to(conn) == ~p"/login"
    end
  end

  describe "re-authentication" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows the email locked", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/login")

      assert html =~ "Confirme seu acesso"
      assert html =~ user.email
    end
  end
end
