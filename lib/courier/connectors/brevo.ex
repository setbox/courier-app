defmodule Courier.Connectors.Brevo do
  @events [
    "delivered",
    "hardBounce",
    "blocked",
    "invalid",
    "spam",
    "opened",
    "click",
    "unsubscribed"
  ]
  @rejected_statuses [400, 401, 402, 403]

  def send_email(api_key, payload) when is_binary(api_key) and is_map(payload) do
    case request(:post, "/smtp/email", api_key, payload) do
      {:ok, %{status: 201, body: %{"messageId" => message_id}}} when is_binary(message_id) ->
        {:ok, %{message_id: normalize_message_id(message_id)}}

      {:ok, %{status: status, body: body}} when status in @rejected_statuses ->
        {:error, {:rejected, nil, error_message(body, status)}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:transient, "HTTP #{status}: #{error_message(body, status)}"}}

      {:error, reason} ->
        {:error, {:transient, inspect(reason)}}
    end
  end

  def upsert_webhook(api_key, webhook_id, url, token) when is_binary(api_key) do
    body = %{
      "url" => url,
      "description" => "Courier",
      "events" => @events,
      "auth" => %{"type" => "bearer", "token" => token}
    }

    case update_webhook(api_key, webhook_id, body) do
      {:ok, id} -> {:ok, id}
      :not_found -> create_webhook(api_key, Map.put(body, "type", "transactional"))
      {:error, reason} -> {:error, reason}
    end
  end

  def upsert_webhook(_api_key, _webhook_id, _url, _token), do: {:error, :missing_api_key}

  def normalize_message_id(message_id) when is_binary(message_id) do
    message_id |> String.trim() |> String.trim_leading("<") |> String.trim_trailing(">")
  end

  def describe_error({:rejected, _code, message}), do: "Brevo: #{message}"
  def describe_error({:transient, message}), do: message
  def describe_error(:missing_api_key), do: "API Key não configurada"
  def describe_error(reason), do: inspect(reason)

  defp update_webhook(_api_key, nil, _body), do: :not_found

  defp update_webhook(api_key, webhook_id, body) do
    case request(:put, "/webhooks/#{webhook_id}", api_key, body) do
      {:ok, %{status: 204}} -> {:ok, webhook_id}
      {:ok, %{status: 404}} -> :not_found
      other -> webhook_error(other)
    end
  end

  defp create_webhook(api_key, body) do
    case request(:post, "/webhooks", api_key, body) do
      {:ok, %{status: 201, body: %{"id" => id}}} -> {:ok, id}
      other -> webhook_error(other)
    end
  end

  defp webhook_error({:ok, %{status: status, body: body}}),
    do: {:error, {:rejected, nil, error_message(body, status)}}

  defp webhook_error({:error, reason}), do: {:error, {:transient, inspect(reason)}}

  defp request(method, path, api_key, body) do
    http().request(
      method: method,
      url: base_url() <> path,
      headers: [
        {"accept", "application/json"},
        {"api-key", api_key}
      ],
      json: body,
      receive_timeout: 15_000,
      retry: false
    )
  end

  defp error_message(%{"code" => code, "message" => message}, _status)
       when is_binary(code) and is_binary(message),
       do: "#{code}: #{message}"

  defp error_message(%{"message" => message}, _status) when is_binary(message), do: message
  defp error_message(_body, status), do: "resposta HTTP #{status}"

  defp http, do: config()[:http] || Req

  defp base_url, do: config()[:base_url]

  defp config, do: Application.get_env(:courier, :brevo, [])
end
