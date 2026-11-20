defmodule CourierWeb.OAuthServerController do
  use CourierWeb, :controller

  alias Courier.OAuth

  def metadata(conn, _params) do
    json(conn, OAuth.metadata())
  end

  def register(conn, params) do
    case OAuth.register_client(params) do
      {:ok, client, secret} ->
        body =
          %{
            "client_id" => client.id,
            "client_id_issued_at" => DateTime.to_unix(client.inserted_at),
            "client_name" => client.name,
            "redirect_uris" => client.redirect_uris,
            "grant_types" => ["authorization_code"],
            "response_types" => ["code"],
            "token_endpoint_auth_method" => client.token_endpoint_auth_method
          }
          |> maybe_put("client_secret", secret)
          |> maybe_put("client_secret_expires_at", secret && 0)

        conn
        |> put_status(:created)
        |> no_store()
        |> json(body)

      {:error, error, description} ->
        conn
        |> put_status(:bad_request)
        |> json(%{"error" => error, "error_description" => description})
    end
  end

  def token(conn, params) do
    case OAuth.exchange_code(params, client_credentials(conn, params)) do
      {:ok, access_token} ->
        conn
        |> no_store()
        |> json(%{
          "access_token" => access_token,
          "token_type" => "Bearer",
          "scope" => OAuth.scope()
        })

      {:error, "invalid_client"} ->
        conn
        |> put_resp_header("www-authenticate", ~s(Basic realm="courier"))
        |> put_status(:unauthorized)
        |> no_store()
        |> json(%{"error" => "invalid_client"})

      {:error, error} ->
        conn
        |> put_status(:bad_request)
        |> no_store()
        |> json(%{"error" => error})
    end
  end

  defp client_credentials(conn, params) do
    with ["Basic " <> encoded] <- get_req_header(conn, "authorization"),
         {:ok, decoded} <- Base.decode64(encoded),
         [id, secret] <- String.split(decoded, ":", parts: 2) do
      {URI.decode_www_form(id), URI.decode_www_form(secret)}
    else
      _ -> {params["client_id"], params["client_secret"]}
    end
  end

  defp no_store(conn), do: put_resp_header(conn, "cache-control", "no-store")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
