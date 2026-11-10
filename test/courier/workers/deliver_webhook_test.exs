defmodule Courier.Workers.DeliverWebhookTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.MessagingFixtures

  alias Courier.Core.{Apps, Emails, Webhooks}
  alias Courier.Core.Webhooks.Delivery
  alias Courier.Webhooks.HttpStub
  alias Courier.Workers.DeliverWebhook

  setup do
    {environment, _token} = configured_environment_fixture()

    {:ok, _env, secret} =
      Apps.update_webhook(environment, %{"webhook_url" => "https://app.test/hook"})

    email = email_fixture(environment, %{"metadata" => %{"order_id" => "7"}})
    {:ok, _} = Emails.mark_sent(email, "pm-1")
    [delivery] = Repo.all(Delivery)
    %{delivery: delivery, secret: secret, email: email}
  end

  test "posts the signed event", %{delivery: delivery, secret: secret, email: email} do
    assert :ok = perform_job(DeliverWebhook, %{delivery_id: delivery.id})

    assert_received {:webhook_post, "https://app.test/hook", opts}
    headers = Map.new(opts[:headers])
    "t=" <> rest = headers["courier-signature"]
    [timestamp, "v1=" <> signature] = String.split(rest, ",")
    assert signature == Webhooks.sign(secret, timestamp, opts[:body])

    body = Jason.decode!(opts[:body])
    assert body["type"] == "email.sent"
    assert body["email"]["id"] == email.id
    assert body["email"]["metadata"] == %{"order_id" => "7"}

    delivery = Repo.get!(Delivery, delivery.id)
    assert delivery.status == :delivered
    assert delivery.response_status == 200
    assert delivery.attempts == 1
  end

  test "non-2xx retries and fails on the last attempt", %{delivery: delivery} do
    HttpStub.respond_with({:ok, %{status: 500}})

    assert {:error, "HTTP 500"} =
             perform_job(DeliverWebhook, %{delivery_id: delivery.id}, attempt: 1)

    assert Repo.get!(Delivery, delivery.id).status == :pending

    assert {:error, _} = perform_job(DeliverWebhook, %{delivery_id: delivery.id}, attempt: 14)
    assert Repo.get!(Delivery, delivery.id).status == :failed
  end

  test "redeliver puts the delivery back on the queue", %{delivery: delivery} do
    HttpStub.respond_with({:error, :econnrefused})
    perform_job(DeliverWebhook, %{delivery_id: delivery.id}, attempt: 14)

    {:ok, delivery} = delivery.id |> Webhooks.get_delivery!() |> Webhooks.redeliver()
    assert delivery.status == :pending
    assert_enqueued(worker: DeliverWebhook, args: %{delivery_id: delivery.id})
  end

  test "backoff grows and is capped at four hours" do
    assert DeliverWebhook.backoff(%Oban.Job{attempt: 1}) == 20
    assert DeliverWebhook.backoff(%Oban.Job{attempt: 13}) == 14_400
  end
end
