defmodule CourierWeb.PostmarkWebhookController do
  use CourierWeb, :controller

  require Logger

  alias Courier.Core.{Apps, Emails}

  def create(conn, %{"environment_id" => environment_id} = params) do
    with %{} = environment <- Apps.get_environment(environment_id),
         %{} = config <- Apps.email_config(environment),
         :ok <- authenticate(conn, config) do
      case Emails.apply_postmark_event(environment, Map.delete(params, "environment_id")) do
        {:ok, _} ->
          json(conn, %{received: true})

        {:error, reason} ->
          Logger.error("postmark webhook not applied: #{inspect(reason)}")
          json(conn, %{received: true, ignored: true})
      end
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    end
  end

  defp authenticate(conn, config) do
    with password when is_binary(password) <- config.inbound_password,
         {username, given} <- Plug.BasicAuth.parse_basic_auth(conn),
         true <- username == Apps.inbound_username(),
         true <- Plug.Crypto.secure_compare(given, password) do
      :ok
    else
      _ -> :unauthorized
    end
  end
end
