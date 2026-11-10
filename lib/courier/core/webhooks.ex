defmodule Courier.Core.Webhooks do
  import Ecto.Query, warn: false

  alias Courier.Core.Apps.Environment
  alias Courier.Core.Emails.{Email, Event}
  alias Courier.Core.Webhooks.Delivery
  alias Courier.Repo
  alias Courier.Workers.DeliverWebhook

  @forwarded [
    :sent,
    :failed,
    :delivery,
    :bounce,
    :spam_complaint,
    :open,
    :click,
    :subscription_change
  ]

  def enqueue(%Email{} = email, %Event{type: type} = event) when type in @forwarded do
    case Repo.get(Environment, email.environment_id) do
      %Environment{webhook_url: url} when is_binary(url) ->
        delivery = Repo.insert!(%Delivery{email_event_id: event.id, url: url})
        Oban.insert!(DeliverWebhook.new(%{delivery_id: delivery.id}))
        {:ok, delivery}

      _ ->
        :skip
    end
  end

  def enqueue(_email, _event), do: :skip

  def list_deliveries(%Email{id: email_id}) do
    Repo.all(
      from d in Delivery,
        join: ev in assoc(d, :email_event),
        where: ev.email_id == ^email_id,
        order_by: [asc: d.inserted_at],
        preload: [email_event: ev]
    )
  end

  def get_delivery!(id) do
    Delivery
    |> Repo.get!(id)
    |> Repo.preload(email_event: [:recipient, email: [:environment]])
  end

  def redeliver(%Delivery{} = delivery) do
    Repo.transact(fn ->
      delivery =
        delivery
        |> Ecto.Changeset.change(status: :pending, response_error: nil)
        |> Repo.update!()

      Oban.insert!(DeliverWebhook.new(%{delivery_id: delivery.id}))
      {:ok, delivery}
    end)
  end

  def deliver(%Delivery{} = delivery, final_attempt?) do
    %Event{email: %Email{environment: environment} = email} = event = delivery.email_event
    body = Jason.encode!(payload(email, event))
    timestamp = System.system_time(:second)

    headers = [
      {"content-type", "application/json"},
      {"user-agent", "Courier-Webhook/1.0"},
      {"courier-event-id", event.id},
      {"courier-signature", signature_header(environment.webhook_secret, timestamp, body)}
    ]

    result =
      http().post(delivery.url,
        headers: headers,
        body: body,
        receive_timeout: 10_000,
        retry: false
      )

    record_attempt(delivery, result, final_attempt?)
  end

  defp record_attempt(delivery, result, final_attempt?) do
    now = DateTime.utc_now(:second)

    {outcome, changes} =
      case result do
        {:ok, %{status: status}} when status in 200..299 ->
          {:ok,
           [status: :delivered, response_status: status, response_error: nil, delivered_at: now]}

        {:ok, %{status: status}} ->
          {{:error, "HTTP #{status}"},
           [response_status: status, response_error: "HTTP #{status}"]}

        {:error, reason} ->
          message = if is_exception(reason), do: Exception.message(reason), else: inspect(reason)
          {{:error, message}, [response_status: nil, response_error: message]}
      end

    changes =
      if outcome != :ok and final_attempt?,
        do: Keyword.put(changes, :status, :failed),
        else: changes

    delivery
    |> Ecto.Changeset.change([attempts: delivery.attempts + 1, last_attempt_at: now] ++ changes)
    |> Repo.update!()

    outcome
  end

  def payload(%Email{} = email, %Event{} = event) do
    %{
      id: event.id,
      type: "email.#{event.type}",
      occurred_at: event.occurred_at,
      email: %{
        id: email.id,
        status: email.status,
        subject: email.subject,
        metadata: email.metadata,
        idempotency_key: email.idempotency_key
      },
      recipient: event.recipient && event.recipient.address,
      data: event.data
    }
  end

  def signature_header(secret, timestamp, body) do
    "t=#{timestamp},v1=#{sign(secret, timestamp, body)}"
  end

  def sign(secret, timestamp, body) do
    :crypto.mac(:hmac, :sha256, secret || "", "#{timestamp}.#{body}")
    |> Base.encode16(case: :lower)
  end

  defp http, do: Application.get_env(:courier, :webhook_http) || Req
end
