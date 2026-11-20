defmodule CourierWeb.DashboardLiveTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.MessagingFixtures

  alias Courier.Core.Emails

  setup :register_and_log_in_user

  setup do
    {environment, _token} = configured_environment_fixture()
    email = email_fixture(environment)
    {:ok, _} = Emails.mark_sent(email, "pm-1", :postmark)
    %{environment: environment}
  end

  test "is the first page, with totals and the three charts", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    assert html =~ "Painel"
    assert has_element?(lv, "#kpis", "Enviados")
    assert has_element?(lv, "#chart-volume")
    assert has_element?(lv, "#chart-problems")
    assert has_element?(lv, "#chart-providers")
    assert html =~ "Últimos 30 dias, por dia"
  end

  test "switches the period and filters by category", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    html = lv |> element("a", "12 meses") |> render_click()
    assert html =~ "Últimos 12 meses, por mês"

    lv |> form("#dashboard_filters", filters: %{category: "marketing"}) |> render_change()
    assert_patch(lv, ~p"/?#{[category: "marketing", period: "12m"]}")
  end

  test "hides a series from the legend", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/")

    html = lv |> element(~s{button[phx-value-key="sent"]}) |> render_click()
    assert html =~ ~s{aria-pressed="false"}
  end
end
