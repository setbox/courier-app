defmodule Courier.Connectors.Google do
  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @userinfo_url "https://www.googleapis.com/oauth2/v3/userinfo"
  @scope "openid email"

  def configured? do
    is_binary(config()[:client_id]) and config()[:client_id] != "" and
      is_binary(config()[:client_secret]) and config()[:client_secret] != ""
  end

  def authorize_url(state, redirect_uri, login_hint \\ nil) when is_binary(state) do
    query =
      %{
        "client_id" => config()[:client_id],
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => @scope,
        "state" => state
      }
      |> Map.merge(account_params(login_hint))
      |> URI.encode_query()

    @authorize_url <> "?" <> query
  end

  defp account_params(nil), do: %{"prompt" => "select_account"}
  defp account_params(login_hint), do: %{"login_hint" => login_hint}

  def fetch_profile(code, redirect_uri) when is_binary(code) do
    with {:ok, token} <- exchange_code(code, redirect_uri),
         {:ok, info} <- fetch_userinfo(token) do
      case info do
        %{"email" => email, "email_verified" => true} when is_binary(email) ->
          {:ok, %{email: String.downcase(email)}}

        %{"email" => _} ->
          {:error, :email_not_verified}

        _ ->
          {:error, :no_email}
      end
    end
  end

  defp exchange_code(code, redirect_uri) do
    form = [
      client_id: config()[:client_id],
      client_secret: config()[:client_secret],
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    ]

    case http().post(@token_url, form: form) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} -> {:ok, token}
      {:ok, %{status: status}} -> {:error, {:token, status}}
      {:error, reason} -> {:error, {:token, reason}}
    end
  end

  defp fetch_userinfo(token) do
    case http().get(@userinfo_url, auth: {:bearer, token}) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:userinfo, status}}
      {:error, reason} -> {:error, {:userinfo, reason}}
    end
  end

  defp http, do: config()[:http] || Req

  defp config, do: Application.get_env(:courier, :google, [])
end
