defmodule Courier.Connectors.Mailtrap do
  @rejected_statuses [400, 401, 403, 404, 413, 422]

  def send_email(api_token, inbox_id, payload)
      when is_binary(api_token) and is_binary(inbox_id) and is_map(payload) do
    case request(api_token, "/api/send/#{inbox_id}", payload) do
      {:ok, %{status: 200, body: %{"message_ids" => [message_id | _]}}} ->
        {:ok, %{message_id: message_id}}

      {:ok, %{status: status, body: body}} when status in @rejected_statuses ->
        {:error, {:rejected, nil, error_message(body, status)}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:transient, "HTTP #{status}: #{error_message(body, status)}"}}

      {:error, reason} ->
        {:error, {:transient, inspect(reason)}}
    end
  end

  defp request(api_token, path, body) do
    http().request(
      method: :post,
      url: base_url() <> path,
      headers: [
        {"accept", "application/json"},
        {"authorization", "Bearer #{api_token}"}
      ],
      json: body,
      receive_timeout: 15_000,
      retry: false
    )
  end

  defp error_message(%{"errors" => errors}, _status) when is_list(errors) and errors != [],
    do: Enum.join(errors, "; ")

  defp error_message(%{"errors" => errors}, _status) when is_binary(errors), do: errors
  defp error_message(%{"error" => error}, _status) when is_binary(error), do: error
  defp error_message(_body, status), do: "resposta HTTP #{status}"

  defp http, do: config()[:http] || Req

  defp base_url, do: config()[:base_url]

  defp config, do: Application.get_env(:courier, :mailtrap, [])
end
