defmodule CourierWeb.UserLive.ConfirmationTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.Core.AccountsFixtures

  alias Courier.Core.Accounts

  setup do
    %{user: unconfirmed_user_fixture()}
  end

  describe "confirmation link" do
    test "posts the token once connected", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, lv, html} = live(conn, ~p"/confirm/#{token}")
      assert html =~ "Confirmando seu e-mail"

      form = form(lv, "#confirm-form")
      render(lv)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "E-mail confirmado"
      assert Accounts.get_user_by_email(user.email).confirmed_at
    end

    test "sends to the resend page with an invalid token", %{conn: conn} do
      conn = post(conn, ~p"/confirm", %{"token" => "invalid"})
      assert redirected_to(conn) == ~p"/confirm"
    end
  end

  describe "resend" do
    test "answers the same whether the account exists or not", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/confirm")

      {:ok, _lv, html} =
        lv
        |> form("#resend_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert html =~ "Se este e-mail tiver conta pendente"
      assert Courier.Repo.get_by(Accounts.UserToken, user_id: user.id, context: "confirm")
    end
  end
end
