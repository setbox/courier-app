defmodule CourierWeb.Api.EmailJSON do
  alias Courier.Core.Emails.{Email, Event, Recipient}

  def accepted(%{email: email}), do: %{id: email.id, status: email.status}

  def show(%{email: email}), do: email(email)

  def index(%{emails: emails, next_cursor: next_cursor}),
    do: %{data: Enum.map(emails, &email/1), next_cursor: next_cursor}

  def events(%{events: events}), do: %{data: Enum.map(events, &event/1)}

  defp email(%Email{} = email) do
    %{
      id: email.id,
      status: email.status,
      from: email.from,
      subject: email.subject,
      reply_to: email.reply_to,
      tag: email.tag,
      message_stream: email.message_stream,
      metadata: email.metadata,
      idempotency_key: email.idempotency_key,
      track_opens: email.track_opens,
      track_links: email.track_links,
      provider_message_id: email.provider_message_id,
      error: error(email),
      attempts: email.attempts,
      created_at: email.inserted_at,
      sent_at: email.sent_at,
      failed_at: email.failed_at,
      recipients: Enum.map(email.recipients, &recipient/1)
    }
  end

  defp error(%Email{error_message: nil}), do: nil

  defp error(%Email{error_code: code, error_message: message}),
    do: %{code: code, message: message}

  defp recipient(%Recipient{} = recipient) do
    %{
      address: recipient.address,
      kind: recipient.kind,
      status: recipient.status,
      status_at: recipient.status_at,
      detail: recipient.detail,
      opened_at: recipient.opened_at,
      clicked_at: recipient.clicked_at
    }
  end

  defp event(%Event{} = event) do
    %{
      id: event.id,
      type: event.type,
      occurred_at: event.occurred_at,
      recipient: event.recipient && event.recipient.address,
      data: event.data
    }
  end
end
