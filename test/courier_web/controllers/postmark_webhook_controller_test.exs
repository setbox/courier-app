defmodule CourierWeb.PostmarkWebhookControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.MessagingFixtures

  alias Courier.Core.{Apps, Emails}

  setup do
    {environment, _token} = configured_environment_fixture()
    email = email_fixture(environment)
    {:ok, _} = Emails.mark_sent(email, "pm-9")
    %{environment: environment, config: Apps.email_config(environment), email: email}
  end

  defp event do
    %{
      "RecordType" => "Delivery",
      "MessageID" => "pm-9",
      "Recipient" => "ana@exemplo.com.br",
      "DeliveredAt" => "2026-11-10T12:00:00Z"
    }
  end

  test "applies the event with valid credentials", %{
    conn: conn,
    environment: environment,
    config: config,
    email: email
  } do
    conn =
      conn
      |> put_req_header(
        "authorization",
        Plug.BasicAuth.encode_basic_auth("courier", config.inbound_password)
      )
      |> post(~p"/webhooks/postmark/#{environment.id}", event())

    assert json_response(conn, 200) == %{"received" => true}
    assert [%{status: :delivered}] = Emails.get_email!(email.id).recipients
  end

  test "refuses a wrong password", %{conn: conn, environment: environment} do
    conn =
      conn
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("courier", "wrong"))
      |> post(~p"/webhooks/postmark/#{environment.id}", event())

    assert json_response(conn, 401)
  end

  test "refuses an unknown environment", %{conn: conn, config: config} do
    conn =
      conn
      |> put_req_header(
        "authorization",
        Plug.BasicAuth.encode_basic_auth("courier", config.inbound_password)
      )
      |> post(~p"/webhooks/postmark/#{Ecto.UUID.generate()}", event())

    assert json_response(conn, 401)
  end
end
