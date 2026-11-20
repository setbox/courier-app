defmodule Courier.Workers.SendEmail do
  use Oban.Worker, queue: :emails, max_attempts: 10

  alias Courier.Connectors.{Brevo, Postmark}
  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig
  alias Courier.Core.Emails
  alias Courier.Core.Emails.Email
  alias Courier.Core.Unsubscribes
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
         {body, unsubscribe_url} = with_unsubscribe(email, body, config),
         {:ok, %{message_id: message_id}} <-
           send_to_provider(config, email, body, unsubscribe_url) do
      {:ok, _} = Emails.mark_sent(email, message_id, config.provider)
      :ok
    else
      {:permanent, code, message} -> fail(email, code, message, provider(config))
      {:error, {:rejected, code, message}} -> fail(email, code, message, provider(config))
      {:error, {:transient, message}} -> retry(email, message, final_attempt?, provider(config))
    end
  end

  defp fetch_body(email) do
    case Emails.fetch_body(email) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:transient, "storage: #{inspect(reason)}"}}
    end
  end

  defp provider(%ChannelConfig{provider: provider}), do: provider
  defp provider(_config), do: nil

  defp fail(email, code, message, provider) do
    {:ok, _} = Emails.mark_failed(email, code, message, provider)
    {:cancel, message}
  end

  defp retry(email, message, true, provider), do: fail(email, nil, message, provider)

  defp retry(email, message, false, _provider) do
    Emails.register_attempt(email, message)
    {:error, message}
  end

  defp with_unsubscribe(%Email{category: :marketing} = email, body, _config) do
    url = unsubscribe_url(email)

    body =
      body
      |> Map.update!(:html_body, &Unsubscribes.with_link(&1, url, :html))
      |> Map.update!(:text_body, &Unsubscribes.with_link(&1, url, :text))

    {body, url}
  end

  defp with_unsubscribe(email, body, %ChannelConfig{provider: :brevo}),
    do: {body, unsubscribe_url(email)}

  defp with_unsubscribe(_email, body, _config), do: {body, nil}

  defp unsubscribe_url(email) do
    %{address: address} = Enum.find(email.recipients, &(&1.kind == :to))
    Unsubscribes.url(email, address)
  end

  defp send_to_provider(%ChannelConfig{provider: :sandbox}, _email, _body, _unsubscribe_url),
    do: {:ok, %{message_id: "sandbox-#{Ecto.UUID.generate()}"}}

  defp send_to_provider(%ChannelConfig{provider: :brevo} = config, email, body, unsubscribe_url),
    do: Brevo.send_email(config.server_token, brevo_payload(email, body, unsubscribe_url))

  defp send_to_provider(%ChannelConfig{} = config, email, body, unsubscribe_url),
    do: Postmark.send_email(config.server_token, payload(email, body, unsubscribe_url))

  defp unsubscribe_headers(nil), do: nil

  defp unsubscribe_headers(url),
    do: %{
      "List-Unsubscribe" => "<#{url}>",
      "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click"
    }

  def brevo_payload(%Email{} = email, body, unsubscribe_url \\ nil) do
    %{
      "sender" => mailbox(email.from),
      "to" => mailboxes(email, :to),
      "cc" => mailboxes(email, :cc),
      "bcc" => mailboxes(email, :bcc),
      "replyTo" => email.reply_to && mailbox(email.reply_to),
      "subject" => email.subject,
      "htmlContent" => body.html_body,
      "textContent" => body.text_body,
      "tags" => email.tag && [email.tag],
      "headers" => unsubscribe_headers(unsubscribe_url)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
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

  def payload(%Email{} = email, body, unsubscribe_url \\ nil) do
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
      "TrackLinks" => if(email.track_links, do: "HtmlAndText", else: "None"),
      "Headers" => postmark_headers(unsubscribe_url)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp postmark_headers(nil), do: nil

  defp postmark_headers(url),
    do:
      url
      |> unsubscribe_headers()
      |> Enum.map(fn {name, value} -> %{"Name" => name, "Value" => value} end)

  defp addresses(%Email{recipients: recipients}, kind) do
    recipients
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.map_join(",", & &1.address)
  end
end
