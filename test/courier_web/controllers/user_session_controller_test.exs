defmodule CourierWeb.UserSessionControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.Core.AccountsFixtures

  describe "DELETE /logout" do
    test "logs the user out", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Sessão encerrada."
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/login"
    end
  end
end
