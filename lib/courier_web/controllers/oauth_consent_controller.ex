defmodule CourierWeb.OAuthConsentController do
  use CourierWeb, :controller

  alias Courier.OAuth

  @forwarded ~w(client_id redirect_uri response_type state code_challenge code_challenge_method scope resource)

  def show(conn, params) do
    case OAuth.validate_authorization(params) do
      {:ok, request} ->
        render(conn, :show,
          request: request,
          hidden: Map.take(params, @forwarded),
          return_host: URI.parse(request.redirect_uri).host
        )

      {:error, reason} when reason in [:invalid_client, :invalid_redirect_uri] ->
        conn |> put_status(:bad_request) |> render(:invalid)

      {:error, {error, description}, redirect_uri, state} ->
        redirect_back(conn, redirect_uri, %{
          "error" => error,
          "error_description" => description,
          "state" => state
        })
    end
  end

  def decide(conn, params) do
    case OAuth.validate_authorization(params) do
      {:ok, request} ->
        if params["decision"] == "allow" do
          code = OAuth.create_code(conn.assigns.current_scope.user, request)
          redirect_back(conn, request.redirect_uri, %{"code" => code, "state" => request.state})
        else
          redirect_back(conn, request.redirect_uri, %{
            "error" => "access_denied",
            "state" => request.state
          })
        end

      {:error, reason} when reason in [:invalid_client, :invalid_redirect_uri] ->
        conn |> put_status(:bad_request) |> render(:invalid)

      {:error, {error, description}, redirect_uri, state} ->
        redirect_back(conn, redirect_uri, %{
          "error" => error,
          "error_description" => description,
          "state" => state
        })
    end
  end

  defp redirect_back(conn, redirect_uri, query) do
    query =
      query
      |> Map.put("iss", OAuth.issuer())
      |> Enum.reject(fn {_, value} -> is_nil(value) end)
      |> URI.encode_query()

    uri = URI.parse(redirect_uri)
    uri = %{uri | query: if(uri.query in [nil, ""], do: query, else: uri.query <> "&" <> query)}

    redirect(conn, external: URI.to_string(uri))
  end
end
