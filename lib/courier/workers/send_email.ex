defmodule Courier.Workers.SendEmail do
  use Oban.Worker, queue: :emails, max_attempts: 10

  alias Courier.Connectors.Postmark
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
         {:ok, %{message_id: message_id}} <-
           Postmark.send_email(config.server_token, payload(email, body)) do
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
