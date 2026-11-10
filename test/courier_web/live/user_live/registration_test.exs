defmodule CourierWeb.UserLive.RegistrationTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.Core.AccountsFixtures

  alias Courier.Core.Accounts

  describe "registration page" do
    test "renders the page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/register")

      assert html =~ "Criar conta"
      assert html =~ "Entrar"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> get(~p"/register")

      assert redirected_to(result) == ~p"/"
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "short"})

      assert result =~ "precisa ter o @ e não pode ter espaços"
      assert result =~ "deve ter entre 8 e 72 caracteres"
    end
  end

  describe "register user" do
    test "creates an unconfirmed account and sends the confirmation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        form
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert html =~ "Enviamos um e-mail de confirmação para #{email}"
      assert %{confirmed_at: nil} = Accounts.get_user_by_email(email)
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/register")
      user = user_fixture()

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "password" => valid_user_password()}
        )
        |> render_submit()

      assert result =~ "já está em uso"
    end
  end
end
