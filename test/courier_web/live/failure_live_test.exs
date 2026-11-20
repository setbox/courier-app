defmodule CourierWeb.FailureLiveTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.MessagingFixtures

  alias Courier.Core.Emails

  setup :register_and_log_in_user

  setup do
    {environment, _token} = configured_environment_fixture()

    failed = email_fixture(environment, %{"subject" => "Fatura recusada"})
    {:ok, _} = Emails.mark_failed(failed, 422, "Inactive recipient", :postmark)

    bounced = email_fixture(environment, %{"subject" => "Endereço inexistente"})

    {:ok, bounced} =
      Emails.mark_sent(Courier.Repo.preload(bounced, :recipients), "pm-b", :postmark)

    {:ok, _} =
      Emails.apply_postmark_event(environment, %{
        "RecordType" => "Bounce",
        "Type" => "HardBounce",
        "MessageID" => bounced.provider_message_id,
        "Email" => "ana@exemplo.com.br",
        "Description" => "User unknown"
      })

    %{environment: environment}
  end

  test "lists failed emails and bounced recipients with counts per type", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/falhas")

    assert html =~ "Fatura recusada"
    assert html =~ "Inactive recipient"
    assert html =~ "Endereço inexistente"
    assert has_element?(lv, "#type-failed", "1")
    assert has_element?(lv, "#type-not_found", "1")
  end

  test "filters by type and by recipient", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/falhas?type=not_found")
    assert has_element?(lv, "#failures", "Endereço inexistente")
    refute has_element?(lv, "#failures", "Fatura recusada")

    {:ok, _lv, html} = live(conn, ~p"/falhas?q=ninguem")
    assert html =~ "Nenhuma falha no período."
  end
end
