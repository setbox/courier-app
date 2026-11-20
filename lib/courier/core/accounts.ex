defmodule Courier.Core.Accounts do
  import Ecto.Query, warn: false
  alias Courier.Repo

  alias Courier.Core.Accounts.{User, UserToken}

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_from_google(%{email: email}) when is_binary(email) do
    case Repo.get_by(User, email: email) do
      nil -> {:error, :not_found}
      %User{confirmed_at: nil} = user -> user |> User.confirm_changeset() |> Repo.update()
      %User{} = user -> {:ok, user}
    end
  end

  def ensure_admin(email) when is_binary(email) do
    case get_user_by_email(email) do
      nil ->
        {:ok, user} =
          %User{}
          |> User.email_changeset(%{email: email})
          |> User.confirm_changeset()
          |> Repo.insert()

        {:created, user}

      %User{} = user ->
        {:existing, user}
    end
  end

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end
end
