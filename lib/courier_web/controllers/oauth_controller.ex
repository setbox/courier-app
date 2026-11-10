defmodule CourierWeb.OAuthController do
  use CourierWeb, :controller

  alias Courier.Connectors.Google
  alias Courier.Core.Accounts
  alias CourierWeb.UserAuth

  @state_key :google_oauth_state

  def request(conn, _params) do
    if Google.configured?() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

      conn
      |> put_session(@state_key, state)
      |> redirect(external: Google.authorize_url(state, callback_url()))
    else
      failed(conn, "A entrada com o Google está indisponível agora. Use e-mail e senha.")
    end
  end

  def callback(conn, %{"error" => _}) do
    conn
    |> delete_session(@state_key)
    |> redirect(to: ~p"/login")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    expected = get_session(conn, @state_key)
    conn = delete_session(conn, @state_key)

    if is_binary(expected) and Plug.Crypto.secure_compare(expected, state) do
      sign_in(conn, code)
    else
      failed(conn, "O link de entrada expirou. Tente de novo.")
    end
  end

  def callback(conn, _params) do
    failed(conn, "Não deu para concluir a entrada com o Google.")
  end

  defp sign_in(conn, code) do
    with {:ok, profile} <- Google.fetch_profile(code, callback_url()),
         {:ok, user} <- Accounts.get_or_register_user_from_google(profile) do
      UserAuth.log_in_user(conn, user)
    else
      {:error, :email_not_verified} ->
        failed(conn, "Esta conta Google não tem e-mail verificado, então não serve para entrar.")

      _ ->
        failed(conn, "Não deu para concluir a entrada com o Google.")
    end
  end

  defp failed(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/login")
  end

  defp callback_url, do: url(~p"/auth/google/callback")
end
