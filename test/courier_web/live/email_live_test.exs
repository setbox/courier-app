defmodule CourierWeb.EmailLiveTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.MessagingFixtures

  alias Courier.Core.{Apps, Emails}

  setup :register_and_log_in_user

  setup do
    {environment, _token} = configured_environment_fixture()
    %{environment: environment, email: email_fixture(environment)}
  end

  test "lists and filters emails", %{conn: conn, environment: environment, email: email} do
    {:ok, lv, html} = live(conn, ~p"/emails")
    assert html =~ email.subject

    html = lv |> form("#filter_form", filters: %{status: "sent"}) |> render_change()
    assert html =~ "Nenhum e-mail encontrado"

    {:ok, _lv, html} = live(conn, ~p"/emails?#{[environment_id: environment.id]}")
    assert html =~ email.subject
  end

  test "shows the detail, the body and redelivers a webhook", %{
    conn: conn,
    environment: environment,
    email: email
  } do
    {:ok, _env, _secret} =
      Apps.update_webhook(environment, %{
        "webhook_url" => "https://app.test/hook",
        "webhook_events" => ["sent", "failed", "delivery"]
      })

    {:ok, _} = Emails.mark_sent(email, "pm-1")

    {:ok, lv, html} = live(conn, ~p"/emails/#{email}")
    assert html =~ "ana@exemplo.com.br"
    assert html =~ "Enviado ao provider"

    assert has_element?(lv, "#email-body iframe")

    html = lv |> element(~s{button[phx-value-view="text"]}) |> render_click()
    assert html =~ "Olá"
    refute has_element?(lv, "#email-body iframe")

    lv |> element(~s{button[phx-value-view="html"]}) |> render_click()
    assert lv |> element(~s{button[phx-value-width="mobile"]}) |> render_click() =~ "w-[375px]"

    html = lv |> element("#deliveries button", "Reenviar") |> render_click()
    assert html =~ "Reenvio agendado"
  end

  test "marks an email kept by the sandbox", %{conn: conn} do
    {environment, _token} = sandbox_environment_fixture()
    email = email_fixture(environment)
    {:ok, _} = Emails.mark_sent(email, "sandbox-1")

    {:ok, lv, _html} = live(conn, ~p"/emails/#{email}")
    assert has_element?(lv, "#sandbox-notice")

    {:ok, lv, _html} = live(conn, ~p"/emails/#{email_fixture(environment)}")
    refute has_element?(lv, "#sandbox-notice")
  end
end
