defmodule CourierWeb.PostmarkWebhookController do
  use CourierWeb, :controller

  require Logger

  alias Courier.Core.{Apps, Emails}
  alias CourierWeb.InboundAuth

  def create(conn, %{"environment_id" => environment_id} = params) do
    with %{} = environment <- Apps.get_environment(environment_id),
         %{} = config <- Apps.email_config(environment),
         :ok <- InboundAuth.authenticate(conn, config) do
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
end
