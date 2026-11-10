defmodule CourierWeb.HomeLiveTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "greets the user", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ user.email
    end
  end
end
