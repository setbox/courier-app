defmodule Courier.Core.EmailsTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.MessagingFixtures

  alias Courier.Core.{Emails, StorageStub}
  alias Courier.Core.Emails.{Email, Event}
  alias Courier.Workers.SendEmail

  setup do
    {environment, _token} = configured_environment_fixture()
    %{environment: environment}
  end

  describe "submit/3" do
    test "stores the body, the recipients and enqueues the send", %{environment: environment} do
      params = email_params(%{"cc" => ["bia@exemplo.com.br"], "metadata" => %{"order_id" => 42}})
      {:ok, email, :created} = Emails.submit(environment, params)

      assert email.status == :queued
      assert email.from == "Exemplo <naoresponda@exemplo.com.br>"
      assert email.metadata == %{"order_id" => 42}

      assert Enum.map(email.recipients, &{&1.kind, &1.address}) == [
               {:to, "ana@exemplo.com.br"},
               {:cc, "bia@exemplo.com.br"}
             ]

      assert {:ok, %{html_body: "<p>Olá</p>", text_body: "Olá"}} = Emails.fetch_body(email)
      assert_enqueued(worker: SendEmail, args: %{email_id: email.id})
      assert [%Event{type: :queued}] = Repo.all(from e in Event, where: e.email_id == ^email.id)
    end

    test "accepts a single address as string and a custom from", %{environment: environment} do
      {:ok, email, :created} =
        Emails.submit(
          environment,
          email_params(%{
            "to" => "ana@exemplo.com.br",
            "from" => "Vendas <vendas@exemplo.com.br>"
          })
        )

      assert email.from == "Vendas <vendas@exemplo.com.br>"
      assert [%{address: "ana@exemplo.com.br"}] = email.recipients
    end

    test "uses the config tracking unless the request overrides it", %{environment: environment} do
      {:ok, email, :created} = Emails.submit(environment, email_params(%{"track_links" => true}))
      assert email.track_links
      refute email.track_opens
    end

    test "refuses an environment without provider" do
      environment = environment_fixture()
      assert {:error, :provider_not_configured} = Emails.submit(environment, email_params())
    end

    test "validates the request", %{environment: environment} do
      {:error, changeset} =
        Emails.submit(environment, %{"to" => ["not-an-email"], "subject" => ""})

      errors = errors_on(changeset)

      assert errors.to == ["invalid address: not-an-email"]
      assert errors.subject
      assert errors.html_body == ["html_body or text_body is required"]
    end

    test "limits recipients and metadata", %{environment: environment} do
      many = for i <- 1..51, do: "p#{i}@exemplo.com.br"

      {:error, changeset} =
        Emails.submit(
          environment,
          email_params(%{"to" => many, "metadata" => %{"a" => %{"b" => 1}}})
        )

      assert errors_on(changeset).to
      assert errors_on(changeset).metadata
    end

    test "rejects the whole request when a recipient is not allowed", %{environment: environment} do
      {:ok, environment} =
        Courier.Core.Apps.update_recipient_lists(environment, %{
          "allowed_recipients" => "@exemplo.com.br",
          "blocked_recipients" => "bia@exemplo.com.br"
        })

      params = email_params(%{"cc" => ["bia@exemplo.com.br"], "bcc" => ["x@fora.com"]})

      assert {:error, {:recipient_not_allowed, ["bia@exemplo.com.br", "x@fora.com"]}} =
               Emails.submit(environment, params)

      assert Repo.aggregate(Email, :count) == 0
      assert {:ok, _email, :created} = Emails.submit(environment, email_params())
    end

    test "replays the same idempotency key", %{environment: environment} do
      {:ok, first, :created} = Emails.submit(environment, email_params(), "key-1")

      {:ok, again, :replayed} =
        Emails.submit(environment, email_params(%{"subject" => "Outro"}), "key-1")

      assert again.id == first.id
      assert Repo.aggregate(Email, :count) == 1
    end

    test "the same key in another environment is a new email", %{environment: environment} do
      {other, _token} = configured_environment_fixture()
      {:ok, first, :created} = Emails.submit(environment, email_params(), "key-1")
      {:ok, second, :created} = Emails.submit(other, email_params(), "key-1")

      refute first.id == second.id
    end

    test "a key older than 24 hours creates a new email", %{environment: environment} do
      {:ok, first, :created} = Emails.submit(environment, email_params(), "key-1")

      Repo.update_all(from(e in Email, where: e.id == ^first.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -25, :hour)]
      )

      {:ok, second, :created} = Emails.submit(environment, email_params(), "key-1")
      refute first.id == second.id
    end

    test "answers storage_unavailable when MinIO fails", %{environment: environment} do
      StorageStub.fail_next_puts()
      assert {:error, :storage_unavailable} = Emails.submit(environment, email_params())
      assert Repo.aggregate(Email, :count) == 0
    end
  end

  describe "apply_postmark_event/2" do
    setup %{environment: environment} do
      email = email_fixture(environment, %{"to" => ["ana@exemplo.com.br", "bia@exemplo.com.br"]})
      {:ok, email} = Emails.mark_sent(Repo.preload(email, :recipients), "pm-1")
      %{email: email}
    end

    test "delivery updates the recipient", %{environment: environment, email: email} do
      {:ok, event} =
        Emails.apply_postmark_event(environment, %{
          "RecordType" => "Delivery",
          "MessageID" => "pm-1",
          "Recipient" => "ANA@exemplo.com.br",
          "DeliveredAt" => "2026-11-10T12:00:00Z"
        })

      assert event.type == :delivery
      recipient = Repo.get!(Emails.Recipient, event.recipient_id)
      assert recipient.status == :delivered
      assert recipient.status_at == ~U[2026-11-10 12:00:00Z]
      assert recipient.email_id == email.id
    end

    test "bounce after delivery wins, delivery after bounce does not", %{environment: environment} do
      base = %{
        "MessageID" => "pm-1",
        "Email" => "bia@exemplo.com.br",
        "Recipient" => "bia@exemplo.com.br"
      }

      {:ok, _} =
        Emails.apply_postmark_event(
          environment,
          Map.merge(base, %{
            "RecordType" => "Bounce",
            "Type" => "HardBounce",
            "Description" => "Unknown user"
          })
        )

      {:ok, event} =
        Emails.apply_postmark_event(environment, Map.put(base, "RecordType", "Delivery"))

      recipient = Repo.get!(Emails.Recipient, event.recipient_id)
      assert recipient.status == :bounced
      assert recipient.detail == "HardBounce: Unknown user"
    end

    test "open and click keep the first time", %{environment: environment} do
      base = %{"MessageID" => "pm-1", "Recipient" => "ana@exemplo.com.br"}

      {:ok, first} =
        Emails.apply_postmark_event(
          environment,
          Map.merge(base, %{"RecordType" => "Open", "ReceivedAt" => "2026-11-10T12:00:00Z"})
        )

      {:ok, _} =
        Emails.apply_postmark_event(
          environment,
          Map.merge(base, %{"RecordType" => "Open", "ReceivedAt" => "2026-11-10T13:00:00Z"})
        )

      {:ok, _} =
        Emails.apply_postmark_event(
          environment,
          Map.merge(base, %{
            "RecordType" => "Click",
            "ReceivedAt" => "2026-11-10T14:00:00Z",
            "OriginalLink" => "https://x"
          })
        )

      recipient = Repo.get!(Emails.Recipient, first.recipient_id)
      assert recipient.opened_at == ~U[2026-11-10 12:00:00Z]
      assert recipient.clicked_at == ~U[2026-11-10 14:00:00Z]
    end

    test "ignores unknown messages and other environments", %{email: _email} do
      {other, _} = configured_environment_fixture()

      payload = %{
        "RecordType" => "Delivery",
        "MessageID" => "pm-1",
        "Recipient" => "ana@exemplo.com.br"
      }

      assert {:ok, :unknown_message} = Emails.apply_postmark_event(other, payload)

      assert {:ok, :ignored} =
               Emails.apply_postmark_event(other, %{"RecordType" => "Inbound", "MessageID" => "x"})
    end
  end

  describe "list_emails/2" do
    test "filters and paginates", %{environment: environment} do
      e1 = email_fixture(environment, %{"metadata" => %{"order_id" => "1"}})
      e2 = email_fixture(environment, %{"to" => ["bia@exemplo.com.br"]})
      e3 = email_fixture(environment)
      {other, _} = configured_environment_fixture()
      _foreign = email_fixture(other)

      {page, cursor} = Emails.list_emails([environment_id: environment.id], limit: 2)
      assert Enum.map(page, & &1.id) == [e3.id, e2.id]
      {page, nil} = Emails.list_emails([environment_id: environment.id], limit: 2, cursor: cursor)
      assert Enum.map(page, & &1.id) == [e1.id]

      assert {[%{id: id}], nil} =
               Emails.list_emails(environment_id: environment.id, to: "bia@exemplo.com.br")

      assert id == e2.id

      assert {[%{id: id}], nil} =
               Emails.list_emails(environment_id: environment.id, metadata: %{"order_id" => "1"})

      assert id == e1.id

      assert {[], nil} = Emails.list_emails(environment_id: environment.id, status: "sent")
      assert {[], nil} = Emails.list_emails(environment_id: environment.id, status: "bogus")

      assert {_three, nil} =
               Emails.list_emails(
                 environment_id: environment.id,
                 from_date: Date.to_iso8601(Date.utc_today())
               )
    end
  end

  describe "purge_expired/1" do
    test "removes emails older than 90 days with their body", %{environment: environment} do
      old = email_fixture(environment)
      recent = email_fixture(environment)

      Repo.update_all(from(e in Email, where: e.id == ^old.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -91, :day)]
      )

      assert Emails.purge_expired(1) == 1
      refute Repo.get(Email, old.id)
      assert Repo.get(Email, recent.id)
      assert {:error, :not_found} = Emails.fetch_body(old)
    end
  end
end
