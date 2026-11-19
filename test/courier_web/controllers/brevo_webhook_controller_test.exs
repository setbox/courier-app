defmodule CourierWeb.BrevoWebhookControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.MessagingFixtures

  alias Courier.Core.{Apps, Emails}

  setup do
    {environment, _token} = brevo_environment_fixture()
    email = email_fixture(environment)
    {:ok, _} = Emails.mark_sent(email, "brevo-9@smtp-relay.mailin.fr")
    %{environment: environment, config: Apps.email_config(environment), email: email}
  end

  defp event do
    %{
      "event" => "delivered",
      "email" => "ana@exemplo.com.br",
      "message-id" => "<brevo-9@smtp-relay.mailin.fr>",
      "ts_event" => 1_794_484_800
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
      |> post(~p"/webhooks/brevo/#{environment.id}", event())

    assert json_response(conn, 200) == %{"received" => true}
    assert [%{status: :delivered}] = Emails.get_email!(email.id).recipients
  end

  test "refuses a missing or wrong password", %{conn: conn, environment: environment} do
    assert conn |> post(~p"/webhooks/brevo/#{environment.id}", event()) |> json_response(401)

    conn =
      conn
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("courier", "wrong"))
      |> post(~p"/webhooks/brevo/#{environment.id}", event())

    assert json_response(conn, 401)
  end
end
