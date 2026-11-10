defmodule CourierWeb.UserLive.ResetPasswordTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.Core.AccountsFixtures

  alias Courier.Core.Accounts

  setup do
    %{user: user_fixture()}
  end

  describe "forgot password" do
    test "sends the link without revealing the account", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/reset-password")
      assert html =~ "Esqueci minha senha"

      {:ok, _lv, html} =
        lv
        |> form("#forgot_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert html =~ "Se este e-mail tiver conta"
      assert Courier.Repo.get_by(Accounts.UserToken, user_id: user.id, context: "reset_password")
    end
  end

  describe "reset password" do
    setup %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{token: token}
    end

    test "resets the password", %{conn: conn, user: user, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/reset-password/#{token}")

      {:ok, _lv, html} =
        lv
        |> form("#reset_form",
          user: %{password: "new valid password", password_confirmation: "new valid password"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert html =~ "Senha redefinida"
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "renders errors", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/reset-password/#{token}")

      result =
        lv
        |> element("#reset_form")
        |> render_change(user: %{password: "short", password_confirmation: "other"})

      assert result =~ "deve ter entre 8 e 72 caracteres"
      assert result =~ "não confere com a senha"
    end

    test "rejects an invalid token", %{conn: conn} do
      {:error, {:live_redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/reset-password/invalid")

      assert path == ~p"/reset-password"
      assert %{"error" => "O link de redefinição é inválido ou expirou."} = flash
    end
  end
end
