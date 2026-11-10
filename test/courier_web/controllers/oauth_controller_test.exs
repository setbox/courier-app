defmodule CourierWeb.OAuthControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.Core.AccountsFixtures

  alias Courier.Connectors.GoogleStub
  alias Courier.Core.Accounts

  defp start_flow(conn) do
    conn = get(conn, ~p"/auth/google")
    state = get_session(conn, :google_oauth_state)
    {recycle(conn) |> Plug.Test.init_test_session(google_oauth_state: state), state}
  end

  test "redirects to Google with the state", %{conn: conn} do
    conn = get(conn, ~p"/auth/google")
    state = get_session(conn, :google_oauth_state)

    assert redirected_to(conn) =~ "https://accounts.google.com/o/oauth2/v2/auth"
    assert redirected_to(conn) =~ "state=#{state}"
  end

  test "creates a confirmed account for a verified email", %{conn: conn} do
    email = unique_user_email()
    GoogleStub.put_userinfo(%{"email" => email, "email_verified" => true})
    {conn, state} = start_flow(conn)

    conn = get(conn, ~p"/auth/google/callback", %{"code" => "code", "state" => state})

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)
    assert Accounts.get_user_by_email(email).confirmed_at
  end

  test "refuses an unverified email", %{conn: conn} do
    email = unique_user_email()
    GoogleStub.put_userinfo(%{"email" => email, "email_verified" => false})
    {conn, state} = start_flow(conn)

    conn = get(conn, ~p"/auth/google/callback", %{"code" => "code", "state" => state})

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "não tem e-mail verificado"
    refute Accounts.get_user_by_email(email)
  end

  test "refuses a wrong state", %{conn: conn} do
    GoogleStub.put_userinfo(%{"email" => unique_user_email(), "email_verified" => true})
    {conn, _state} = start_flow(conn)

    conn = get(conn, ~p"/auth/google/callback", %{"code" => "code", "state" => "forged"})

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expirou"
    refute get_session(conn, :user_token)
  end

  test "treats cancellation as a quiet return", %{conn: conn} do
    conn = get(conn, ~p"/auth/google/callback", %{"error" => "access_denied"})

    assert redirected_to(conn) == ~p"/login"
    refute Phoenix.Flash.get(conn.assigns.flash, :error)
  end
end
