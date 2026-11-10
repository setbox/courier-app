defmodule CourierWeb.EnvironmentLiveTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.MessagingFixtures

  alias Courier.Core.Apps

  setup :register_and_log_in_user

  setup do
    %{environment: environment_fixture()}
  end

  defp env_path(environment, suffix \\ ""),
    do: "/apps/#{environment.app_id}/environments/#{environment.id}#{suffix}"

  test "the detail page has no form", %{conn: conn, environment: environment} do
    {:ok, _lv, html} = live(conn, env_path(environment))
    refute html =~ "<form"
    assert html =~ "Configurar e-mail"
  end

  test "generates the token and shows it once", %{conn: conn, environment: environment} do
    {:ok, lv, _html} = live(conn, env_path(environment))

    html = lv |> element("#regenerate-token") |> render_click()
    [token] = Regex.run(~r/cl_[A-Za-z0-9_-]{40,}/, html)
    assert Apps.get_environment_by_client_token(token).id == environment.id

    {:ok, _lv, html} = live(conn, env_path(environment))
    refute html =~ token
    assert html =~ "cl_…#{String.slice(token, -4, 4)}"
  end

  test "renames the environment", %{conn: conn, environment: environment} do
    {:ok, lv, _html} = live(conn, env_path(environment, "/edit"))

    {:ok, _lv, html} =
      lv
      |> form("#environment_form", environment: %{name: "produção"})
      |> render_submit()
      |> follow_redirect(conn, env_path(environment))

    assert html =~ "produção"
  end

  test "saves the email config in its own page", %{conn: conn, environment: environment} do
    {:ok, lv, _html} = live(conn, env_path(environment, "/email"))

    {:ok, _lv, html} =
      lv
      |> form("#config_form",
        channel_config: %{
          server_token: "tok-9876",
          from_email: "a@exemplo.com.br",
          message_stream: "outbound"
        }
      )
      |> render_submit()
      |> follow_redirect(conn, env_path(environment))

    assert html =~ "webhook cadastrado no Postmark"
    assert html =~ "/webhooks/postmark/#{environment.id}"
    assert html =~ "••••9876"
    refute html =~ "tok-9876"
  end

  test "keeps the user on the email page when invalid", %{conn: conn, environment: environment} do
    {:ok, lv, _html} = live(conn, env_path(environment, "/email"))
    html = lv |> form("#config_form", channel_config: %{from_email: "x"}) |> render_submit()
    assert html =~ "informe o Server API Token do Postmark"
  end

  test "saves the recipient lists in their own page", %{conn: conn, environment: environment} do
    {:ok, lv, _html} = live(conn, env_path(environment, "/recipients"))

    html =
      lv
      |> form("#recipients_form",
        recipients: %{allowed_recipients: "@setbox.com.br", blocked_recipients: "x"}
      )
      |> render_submit()

    assert html =~ "entradas inválidas: x"

    {:ok, _lv, html} =
      lv
      |> form("#recipients_form",
        recipients: %{allowed_recipients: "@setbox.com.br", blocked_recipients: ""}
      )
      |> render_submit()
      |> follow_redirect(conn, env_path(environment))

    assert html =~ "Listas de destinatários salvas"
    assert html =~ "@setbox.com.br"
  end

  test "sets the client webhook and shows the secret once", %{
    conn: conn,
    environment: environment
  } do
    {:ok, lv, _html} = live(conn, env_path(environment, "/webhook"))

    html =
      lv
      |> form("#webhook_form", environment: %{webhook_url: "https://app.test/hook"})
      |> render_submit()

    assert html =~ "whsec_"
    assert Apps.get_environment(environment.id).webhook_url == "https://app.test/hook"

    {:ok, lv, _html} = live(conn, env_path(environment, "/webhook"))

    {:ok, _lv, html} =
      lv
      |> form("#webhook_form", environment: %{webhook_url: "https://app.test/other"})
      |> render_submit()
      |> follow_redirect(conn, env_path(environment))

    assert html =~ "https://app.test/other"
    refute html =~ "whsec_"
  end
end
