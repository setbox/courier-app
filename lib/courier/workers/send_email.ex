defmodule Courier.Workers.SendEmail do
  use Oban.Worker, queue: :emails, max_attempts: 10

  alias Courier.Connectors.{Brevo, Mailtrap, Postmark}
  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig
  alias Courier.Core.Emails
  alias Courier.Core.Emails.Email
  alias Courier.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_id" => email_id}, attempt: attempt, max_attempts: max}) do
    case Repo.get(Email, email_id) do
      %Email{status: :queued} = email ->
        deliver(Repo.preload(email, [:recipients, :environment]), attempt >= max)

      _ ->
        :ok
    end
  end

  defp deliver(email, final_attempt?) do
    config = Apps.email_config(email.environment)

    with true <- ChannelConfig.ready?(config) || {:permanent, nil, "provider not configured"},
         {:ok, body} <- fetch_body(email),
         {:ok, %{message_id: message_id}} <- send_to_provider(config, email, body) do
      {:ok, _} = Emails.mark_sent(email, message_id)
      :ok
    else
      {:permanent, code, message} -> fail(email, code, message)
      {:error, {:rejected, code, message}} -> fail(email, code, message)
      {:error, {:transient, message}} -> retry(email, message, final_attempt?)
    end
  end

  defp fetch_body(email) do
    case Emails.fetch_body(email) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:transient, "storage: #{inspect(reason)}"}}
    end
  end

  defp fail(email, code, message) do
    {:ok, _} = Emails.mark_failed(email, code, message)
    {:cancel, message}
  end

  defp retry(email, message, true), do: fail(email, nil, message)

  defp retry(email, message, false) do
    Emails.register_attempt(email, message)
    {:error, message}
  end

  defp send_to_provider(%ChannelConfig{provider: :mailtrap_sandbox} = config, email, body),
    do:
      Mailtrap.send_email(
        config.server_token,
        config.mailtrap_inbox_id,
        mailtrap_payload(email, body)
      )

  defp send_to_provider(%ChannelConfig{provider: :brevo} = config, email, body),
    do: Brevo.send_email(config.server_token, brevo_payload(email, body))

  defp send_to_provider(%ChannelConfig{} = config, email, body),
    do: Postmark.send_email(config.server_token, payload(email, body))

  def brevo_payload(%Email{} = email, body) do
    %{
      "sender" => mailbox(email.from),
      "to" => mailboxes(email, :to),
      "cc" => mailboxes(email, :cc),
      "bcc" => mailboxes(email, :bcc),
      "replyTo" => email.reply_to && mailbox(email.reply_to),
      "subject" => email.subject,
      "htmlContent" => body.html_body,
      "textContent" => body.text_body,
      "tags" => email.tag && [email.tag]
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  def mailtrap_payload(%Email{} = email, body) do
    %{
      "from" => mailbox(email.from),
      "to" => mailboxes(email, :to),
      "cc" => mailboxes(email, :cc),
      "bcc" => mailboxes(email, :bcc),
      "reply_to" => email.reply_to && mailbox(email.reply_to),
      "subject" => email.subject,
      "html" => body.html_body,
      "text" => body.text_body,
      "category" => email.tag,
      "custom_variables" => custom_variables(email.metadata)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", [], %{}] end)
    |> Map.new()
  end

  defp mailbox(address) do
    case Regex.run(~r/^\s*(.*?)\s*<([^>]+)>\s*$/, address) do
      [_, "", email] -> %{"email" => email}
      [_, name, email] -> %{"email" => email, "name" => String.trim(name, "\"")}
      nil -> %{"email" => String.trim(address)}
    end
  end

  defp mailboxes(%Email{recipients: recipients}, kind) do
    recipients
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.map(&%{"email" => &1.address})
  end

  defp custom_variables(metadata) when is_map(metadata),
    do: Map.new(metadata, fn {key, value} -> {to_string(key), to_string(value)} end)

  defp custom_variables(_metadata), do: %{}

  def payload(%Email{} = email, body) do
    %{
      "From" => email.from,
      "To" => addresses(email, :to),
      "Cc" => addresses(email, :cc),
      "Bcc" => addresses(email, :bcc),
      "ReplyTo" => email.reply_to,
      "Subject" => email.subject,
      "HtmlBody" => body.html_body,
      "TextBody" => body.text_body,
      "Tag" => email.tag,
      "MessageStream" => email.message_stream,
      "TrackOpens" => email.track_opens,
      "TrackLinks" => if(email.track_links, do: "HtmlAndText", else: "None")
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp addresses(%Email{recipients: recipients}, kind) do
    recipients
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.map_join(",", & &1.address)
  end
end
