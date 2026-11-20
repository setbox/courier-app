defmodule CourierWeb.ProviderLiveTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.MessagingFixtures

  setup :register_and_log_in_user

  test "lists every provider with how many environments use it", %{conn: conn} do
    brevo_environment_fixture()

    {:ok, _lv, html} = live(conn, ~p"/providers")

    assert html =~ "Postmark"
    assert html =~ "Sandbox do Courier"
    assert html =~ "Brevo"
    assert html =~ "1 ambiente"
    refute html =~ "<form"
  end

  test "shows the environments that use a provider", %{conn: conn} do
    {environment, _token} = brevo_environment_fixture(name: "stage")
    {other, _token} = configured_environment_fixture(name: "prod")

    {:ok, lv, html} = live(conn, ~p"/providers/brevo")

    assert html =~ "#{environment.app.name} / stage"
    refute has_element?(lv, "#environment-#{other.id}")
  end

  test "shows an empty state when nobody uses the provider", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/providers/sandbox")
    assert html =~ "Nenhum ambiente usa este provider."
  end

  test "an unknown provider is not found", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/providers/sendgrid") end
  end
end
