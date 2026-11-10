defmodule CourierWeb.UserSessionController do
  use CourierWeb, :controller

  alias Courier.Core.Accounts
  alias CourierWeb.UserAuth

  def create(conn, %{"user" => %{"email" => email, "password" => password} = params}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %{confirmed_at: nil} ->
        conn
        |> put_flash(
          :error,
          "Confirme seu e-mail antes de entrar. O link foi enviado no cadastro."
        )
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/login")

      %{} = user ->
        conn
        |> store_return_to(UserAuth.local_path(params["return_to"]))
        |> UserAuth.log_in_user(user, params)

      nil ->
        conn
        |> put_flash(:error, "E-mail ou senha inválidos.")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/login")
    end
  end

  def confirm(conn, %{"token" => token}) when is_binary(token) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "E-mail confirmado. Boas-vindas ao Courier!")
        |> UserAuth.log_in_user(user)

      :error ->
        redirect(conn, to: ~p"/confirm")
    end
  end

  def confirm(conn, _params), do: redirect(conn, to: ~p"/confirm")

  def update_password(conn, %{"user" => params}) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.update_user_password(user, params) do
      {:ok, {user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_flash(:info, "Senha alterada. As outras sessões foram encerradas.")
        |> put_session(:user_return_to, ~p"/settings")
        |> UserAuth.log_in_user(user)

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Não deu para trocar a senha. Confira os campos e tente de novo.")
        |> redirect(to: ~p"/settings")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Sessão encerrada.")
    |> UserAuth.log_out_user()
  end

  defp store_return_to(conn, nil), do: conn
  defp store_return_to(conn, path), do: put_session(conn, :user_return_to, path)
end
