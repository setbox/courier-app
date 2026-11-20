defmodule CourierWeb.UserLive.LoginTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.Core.AccountsFixtures

  test "offers only the Google login", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/login")

    assert html =~ "Entrar"
    assert html =~ "Continuar com o Google"
    refute has_element?(lv, "form")
    refute html =~ "Senha"
  end

  test "has no password, registration, reset or confirmation routes", %{conn: conn} do
    assert get(conn, "/register").status == 404
    assert get(conn, "/reset-password").status == 404
    assert get(conn, "/confirm").status == 404
    assert post(conn, "/login", %{"user" => %{"email" => "a@b.c"}}).status == 404
  end

  test "sends a signed-in user home", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/login")
  end
end
