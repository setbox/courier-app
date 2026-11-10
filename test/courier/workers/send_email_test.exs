defmodule Courier.Workers.SendEmailTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.MessagingFixtures

  alias Courier.Connectors.PostmarkStub
  alias Courier.Core.{Apps, Emails}
  alias Courier.Core.Emails.Email
  alias Courier.Workers.{DeliverWebhook, SendEmail}

  setup do
    {environment, _token} = configured_environment_fixture()

    email =
      email_fixture(environment, %{
        "cc" => ["bia@exemplo.com.br"],
        "tag" => "welcome",
        "track_links" => true
      })

    %{environment: environment, email: email}
  end

  test "sends to Postmark and marks as sent", %{email: email} do
    PostmarkStub.respond_with(fn opts ->
      send(self(), {:email_payload, opts})
      {:ok, %{status: 200, body: %{"MessageID" => "pm-42", "SubmittedAt" => "x"}}}
    end)

    assert :ok = perform_job(SendEmail, %{email_id: email.id})

    assert_received {:email_payload, opts}
    assert opts[:url] == "https://postmark.test/email"
    assert {"x-postmark-server-token", "server-token-1234"} in opts[:headers]

    assert opts[:json] == %{
             "From" => "Exemplo <naoresponda@exemplo.com.br>",
             "To" => "ana@exemplo.com.br",
             "Cc" => "bia@exemplo.com.br",
             "Subject" => "Bem-vinda",
             "HtmlBody" => "<p>Olá</p>",
             "TextBody" => "Olá",
             "Tag" => "welcome",
             "MessageStream" => "outbound",
             "TrackOpens" => false,
             "TrackLinks" => "HtmlAndText"
           }

    email = Repo.get!(Email, email.id)
    assert email.status == :sent
    assert email.provider_message_id == "pm-42"
    assert email.sent_at
    assert email.attempts == 1
  end

  test "a Postmark rejection fails at once", %{email: email} do
    PostmarkStub.respond_with(fn _ ->
      {:ok, %{status: 422, body: %{"ErrorCode" => 406, "Message" => "Inactive recipient"}}}
    end)

    assert {:cancel, "Inactive recipient"} = perform_job(SendEmail, %{email_id: email.id})

    email = Repo.get!(Email, email.id)
    assert email.status == :failed
    assert email.error_code == 406
    assert email.failed_at
  end

  test "a transient error retries and fails on the last attempt", %{email: email} do
    PostmarkStub.respond_with(fn _ -> {:ok, %{status: 503, body: ""}} end)

    assert {:error, _} = perform_job(SendEmail, %{email_id: email.id}, attempt: 1)
    assert Repo.get!(Email, email.id).status == :queued

    assert {:cancel, _} = perform_job(SendEmail, %{email_id: email.id}, attempt: 10)
    assert Repo.get!(Email, email.id).status == :failed
  end

  test "does nothing for an email already sent", %{email: email} do
    {:ok, _} = Emails.mark_sent(email, "pm-1")
    assert :ok = perform_job(SendEmail, %{email_id: email.id})

    refute_received {:postmark_request,
                     [{:method, :post}, {:url, "https://postmark.test/email"} | _]}
  end

  test "enqueues the client webhook when configured", %{environment: environment, email: email} do
    {:ok, _env, _secret} =
      Apps.update_webhook(environment, %{"webhook_url" => "https://app.test/hook"})

    assert :ok = perform_job(SendEmail, %{email_id: email.id})
    assert [%{args: %{"delivery_id" => _}}] = all_enqueued(worker: DeliverWebhook)
  end
end
