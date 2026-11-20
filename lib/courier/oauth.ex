defmodule Courier.OAuth do
  import Ecto.Query, warn: false

  alias Courier.Core.Accounts
  alias Courier.Core.Accounts.User
  alias Courier.OAuth.{Client, Code}
  alias Courier.Repo

  @code_validity_in_seconds 600
  @auth_methods ~w(none client_secret_post client_secret_basic)
  @max_redirect_uris 10
  @max_name_length 100
  @scope "mcp"

  def scope, do: @scope

  def issuer do
    uri = URI.parse(Courier.MCP.Server.resource())
    URI.to_string(%{uri | path: nil, query: nil, fragment: nil})
  end

  def metadata do
    issuer = issuer()

    %{
      "issuer" => issuer,
      "authorization_endpoint" => issuer <> "/oauth/authorize",
      "token_endpoint" => issuer <> "/oauth/token",
      "registration_endpoint" => issuer <> "/oauth/register",
      "response_types_supported" => ["code"],
      "grant_types_supported" => ["authorization_code"],
      "code_challenge_methods_supported" => ["S256"],
      "token_endpoint_auth_methods_supported" => @auth_methods,
      "scopes_supported" => [@scope]
    }
  end

  def register_client(params) when is_map(params) do
    method = Map.get(params, "token_endpoint_auth_method", "none")

    with {:ok, uris} <- validate_redirect_uris(Map.get(params, "redirect_uris")),
         :ok <- validate_auth_method(method) do
      name = client_name(Map.get(params, "client_name"))
      {secret, secret_hash} = maybe_secret(method)

      client =
        Repo.insert!(%Client{
          name: name,
          redirect_uris: uris,
          token_endpoint_auth_method: method,
          secret_hash: secret_hash
        })

      {:ok, client, secret}
    end
  end

  def register_client(_), do: {:error, "invalid_client_metadata", "Expected a JSON object."}

  defp validate_redirect_uris([_ | _] = uris) when length(uris) <= @max_redirect_uris do
    if Enum.all?(uris, &valid_redirect_uri?/1) do
      {:ok, uris}
    else
      {:error, "invalid_redirect_uri",
       "Redirect URIs must be https, or http on localhost, without a fragment."}
    end
  end

  defp validate_redirect_uris(_),
    do: {:error, "invalid_redirect_uri", "redirect_uris must list 1 to 10 URIs."}

  defp valid_redirect_uri?(uri) when is_binary(uri) and byte_size(uri) <= 2000 do
    case URI.parse(uri) do
      %URI{scheme: "https", host: host, fragment: nil} when is_binary(host) and host != "" ->
        true

      %URI{scheme: "http", host: host, fragment: nil}
      when host in ["localhost", "127.0.0.1", "::1"] ->
        true

      _ ->
        false
    end
  end

  defp valid_redirect_uri?(_), do: false

  defp validate_auth_method(method) when method in @auth_methods, do: :ok

  defp validate_auth_method(_),
    do: {:error, "invalid_client_metadata", "Unsupported token_endpoint_auth_method."}

  defp client_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "MCP client"
      trimmed -> String.slice(trimmed, 0, @max_name_length)
    end
  end

  defp client_name(_), do: "MCP client"

  defp maybe_secret("none"), do: {nil, nil}

  defp maybe_secret(_method) do
    secret = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    {secret, :crypto.hash(:sha256, secret)}
  end

  def get_client(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Client, uuid)
      :error -> nil
    end
  end

  def validate_authorization(params) do
    state = params["state"]

    with {:client, %Client{} = client} <- {:client, get_client(params["client_id"])},
         {:redirect, redirect_uri} when is_binary(redirect_uri) <-
           {:redirect, pick_redirect_uri(client, params["redirect_uri"])},
         :ok <- check_response_type(params["response_type"]),
         :ok <- check_pkce(params["code_challenge"], params["code_challenge_method"]) do
      {:ok,
       %{
         client: client,
         redirect_uri: redirect_uri,
         state: state,
         code_challenge: params["code_challenge"]
       }}
    else
      {:client, _} -> {:error, :invalid_client}
      {:redirect, _} -> {:error, :invalid_redirect_uri}
      {:error, error} -> {:error, error, pick_redirect_uri_raw(params), state}
    end
  end

  defp pick_redirect_uri(%Client{redirect_uris: [only]}, nil), do: only

  defp pick_redirect_uri(%Client{redirect_uris: uris}, uri) when is_binary(uri) do
    if uri in uris, do: uri
  end

  defp pick_redirect_uri(_, _), do: nil

  defp pick_redirect_uri_raw(params) do
    client = get_client(params["client_id"])
    pick_redirect_uri(client, params["redirect_uri"])
  end

  defp check_response_type("code"), do: :ok

  defp check_response_type(_),
    do: {:error, {"unsupported_response_type", "Only response_type=code is supported."}}

  defp check_pkce(challenge, "S256")
       when is_binary(challenge) and byte_size(challenge) in 43..128,
       do: :ok

  defp check_pkce(_, _),
    do: {:error, {"invalid_request", "PKCE with code_challenge_method=S256 is required."}}

  def create_code(%User{} = user, %{client: client} = request) do
    code = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    Repo.insert!(%Code{
      code_hash: :crypto.hash(:sha256, code),
      client_id: client.id,
      user_id: user.id,
      redirect_uri: request.redirect_uri,
      code_challenge: request.code_challenge,
      expires_at: DateTime.add(DateTime.utc_now(:second), @code_validity_in_seconds)
    })

    code
  end

  def exchange_code(params, {client_id, client_secret}) do
    with {:grant, "authorization_code"} <- {:grant, params["grant_type"]},
         {:ok, client} <- authenticate_client(client_id, client_secret),
         {:ok, code} <- consume_code(client, params["code"]),
         :ok <- check_code(code, params),
         {:ok, raw, _token} <- Accounts.create_mcp_token(code.user, client.name) do
      {:ok, raw}
    else
      {:grant, _} -> {:error, "unsupported_grant_type"}
      {:error, error} when is_binary(error) -> {:error, error}
      {:error, _} -> {:error, "invalid_grant"}
    end
  end

  defp authenticate_client(client_id, secret) do
    case get_client(client_id) do
      %Client{secret_hash: nil} = client ->
        {:ok, client}

      %Client{secret_hash: hash} = client when is_binary(secret) ->
        if Plug.Crypto.secure_compare(hash, :crypto.hash(:sha256, secret)),
          do: {:ok, client},
          else: {:error, "invalid_client"}

      _ ->
        {:error, "invalid_client"}
    end
  end

  defp consume_code(client, raw) when is_binary(raw) do
    hash = :crypto.hash(:sha256, raw)

    query =
      from c in Code,
        where: c.code_hash == ^hash and c.client_id == ^client.id,
        select: c

    case Repo.delete_all(query) do
      {1, [code]} -> {:ok, Repo.preload(code, :user)}
      _ -> {:error, "invalid_grant"}
    end
  end

  defp consume_code(_, _), do: {:error, "invalid_request"}

  defp check_code(code, params) do
    cond do
      DateTime.compare(code.expires_at, DateTime.utc_now()) != :gt -> {:error, "invalid_grant"}
      params["redirect_uri"] not in [nil, code.redirect_uri] -> {:error, "invalid_grant"}
      not pkce_valid?(params["code_verifier"], code.code_challenge) -> {:error, "invalid_grant"}
      true -> :ok
    end
  end

  defp pkce_valid?(verifier, challenge) when is_binary(verifier) do
    computed = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)
    Plug.Crypto.secure_compare(computed, challenge)
  end

  defp pkce_valid?(_, _), do: false
end
