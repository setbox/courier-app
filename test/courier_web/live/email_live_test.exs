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
      Apps.update_webhook(environment, %{"webhook_url" => "https://app.test/hook"})

    {:ok, _} = Emails.mark_sent(email, "pm-1")

    {:ok, lv, html} = live(conn, ~p"/emails/#{email}")
    assert html =~ "ana@exemplo.com.br"
    assert html =~ "Enviado ao Postmark"

    html = lv |> element("#show-body") |> render_click()
    assert html =~ "Olá"

    html = lv |> element("#deliveries button", "Reenviar") |> render_click()
    assert html =~ "Reenvio agendado"
  end
end
