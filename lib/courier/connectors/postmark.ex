defmodule Courier.Connectors.Postmark do
  @triggers %{
    "Open" => %{"Enabled" => true, "PostFirstOpenOnly" => false},
    "Click" => %{"Enabled" => true},
    "Delivery" => %{"Enabled" => true},
    "Bounce" => %{"Enabled" => true, "IncludeContent" => false},
    "SpamComplaint" => %{"Enabled" => true, "IncludeContent" => false},
    "SubscriptionChange" => %{"Enabled" => true}
  }

  def send_email(server_token, payload) when is_binary(server_token) and is_map(payload) do
    case request(:post, "/email", server_token, payload) do
      {:ok, %{status: 200, body: %{"MessageID" => message_id} = body}} ->
        {:ok, %{message_id: message_id, submitted_at: body["SubmittedAt"]}}

      {:ok, %{status: status, body: body}} when status in [401, 422] ->
        {:error, {:rejected, error_code(body), error_message(body, status)}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:transient, "HTTP #{status}: #{error_message(body, status)}"}}

      {:error, reason} ->
        {:error, {:transient, inspect(reason)}}
    end
  end

  def upsert_webhook(server_token, webhook_id, attrs) when is_binary(server_token) do
    body = %{
      "Url" => attrs.url,
      "MessageStream" => attrs.message_stream,
      "HttpAuth" => %{"Username" => attrs.username, "Password" => attrs.password},
      "Triggers" => @triggers
    }

    case update_webhook(server_token, webhook_id, body) do
      {:ok, id} -> {:ok, id}
      :not_found -> create_webhook(server_token, body)
      {:error, reason} -> {:error, reason}
    end
  end

  def upsert_webhook(_server_token, _webhook_id, _attrs), do: {:error, :missing_server_token}

  def describe_error({:rejected, code, message}), do: "Postmark #{code}: #{message}"
  def describe_error({:transient, message}), do: message
  def describe_error(:missing_server_token), do: "Server API Token não configurado"
  def describe_error(reason), do: inspect(reason)

  defp update_webhook(_server_token, nil, _body), do: :not_found

  defp update_webhook(server_token, webhook_id, body) do
    case request(:put, "/webhooks/#{webhook_id}", server_token, body) do
      {:ok, %{status: 200, body: %{"ID" => id}}} -> {:ok, id}
      {:ok, %{status: status}} when status in [404, 422] -> :not_found
      other -> webhook_error(other)
    end
  end

  defp create_webhook(server_token, body) do
    case request(:post, "/webhooks", server_token, body) do
      {:ok, %{status: 200, body: %{"ID" => id}}} -> {:ok, id}
      other -> webhook_error(other)
    end
  end

  defp webhook_error({:ok, %{status: status, body: body}}),
    do: {:error, {:rejected, error_code(body), error_message(body, status)}}

  defp webhook_error({:error, reason}), do: {:error, {:transient, inspect(reason)}}

  defp request(method, path, server_token, body) do
    http().request(
      method: method,
      url: base_url() <> path,
      headers: [
        {"accept", "application/json"},
        {"x-postmark-server-token", server_token}
      ],
      json: body,
      receive_timeout: 15_000,
      retry: false
    )
  end

  defp error_code(%{"ErrorCode" => code}) when is_integer(code), do: code
  defp error_code(_body), do: nil

  defp error_message(%{"Message" => message}, _status) when is_binary(message), do: message
  defp error_message(_body, status), do: "resposta HTTP #{status}"

  defp http, do: config()[:http] || Req

  defp base_url, do: config()[:base_url]

  defp config, do: Application.get_env(:courier, :postmark, [])
end
