defmodule CourierWeb.Api.EmailController do
  use CourierWeb, :controller

  alias Courier.Core.Emails
  alias CourierWeb.Api.Error

  @filters ~w(status to from_date to_date idempotency_key)

  def create(conn, params) do
    environment = conn.assigns.environment
    idempotency_key = conn |> get_req_header("idempotency-key") |> List.first()

    case Emails.submit(environment, params, idempotency_key) do
      {:ok, email, outcome} ->
        conn
        |> put_resp_header("idempotent-replayed", to_string(outcome == :replayed))
        |> put_status(:accepted)
        |> render(:accepted, email: email)

      {:error, :provider_not_configured} ->
        Error.send(
          conn,
          422,
          "provider_not_configured",
          "The environment has no email provider configured"
        )

      {:error, {:recipient_not_allowed, addresses}} ->
        Error.send(
          conn,
          422,
          "recipient_not_allowed",
          "Some recipients are not allowed in this environment",
          %{recipients: addresses}
        )

      {:error, :storage_unavailable} ->
        Error.send(conn, 503, "storage_unavailable", "Could not store the message, try again")

      {:error, %Ecto.Changeset{} = changeset} ->
        Error.send(
          conn,
          422,
          "invalid_request",
          "The request has invalid fields",
          Error.changeset_details(changeset)
        )
    end
  end

  def index(conn, params) do
    filters =
      params
      |> Map.take(@filters)
      |> Enum.map(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Keyword.put(:environment_id, conn.assigns.environment.id)
      |> Keyword.put(:metadata, metadata_filter(params["metadata"]))

    {emails, next_cursor} =
      Emails.list_emails(filters, cursor: params["cursor"], limit: params["limit"])

    render(conn, :index, emails: emails, next_cursor: next_cursor)
  end

  def show(conn, %{"id" => id}) do
    case Emails.get_email(conn.assigns.environment, id) do
      nil -> not_found(conn)
      email -> render(conn, :show, email: email)
    end
  end

  def events(conn, %{"email_id" => id}) do
    case Emails.get_email(conn.assigns.environment, id) do
      nil -> not_found(conn)
      email -> render(conn, :events, events: Emails.list_events(email))
    end
  end

  defp metadata_filter(%{} = metadata), do: metadata
  defp metadata_filter(_metadata), do: nil

  defp not_found(conn), do: Error.send(conn, 404, "not_found", "Email not found")
end
