defmodule CourierWeb.UserSessionControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.Core.AccountsFixtures

  describe "POST /login" do
    test "logs the user in", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "honors a local return_to", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "return_to" => "/settings"
          }
        })

      assert redirected_to(conn) == ~p"/settings"
    end

    test "ignores an external return_to", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "return_to" => "//evil.com"
          }
        })

      assert redirected_to(conn) == ~p"/"
    end

    test "refuses an unconfirmed user", %{conn: conn} do
      user = unconfirmed_user_fixture()

      conn =
        post(conn, ~p"/login", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Confirme seu e-mail"
      assert redirected_to(conn) == ~p"/login"
    end

    test "answers the same for wrong password and unknown email", %{conn: conn} do
      user = user_fixture()

      wrong =
        post(conn, ~p"/login", %{"user" => %{"email" => user.email, "password" => "wrong pass"}})

      unknown =
        post(conn, ~p"/login", %{
          "user" => %{"email" => "nobody@example.com", "password" => "wrong pass"}
        })

      for conn <- [wrong, unknown] do
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "E-mail ou senha inválidos."
        assert redirected_to(conn) == ~p"/login"
      end
    end
  end

  describe "DELETE /logout" do
    test "logs the user out", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Sessão encerrada."
    end
  end
end
