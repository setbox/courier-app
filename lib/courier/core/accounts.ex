defmodule Courier.Core.Accounts do
  import Ecto.Query, warn: false
  alias Courier.Repo

  alias Courier.Core.Accounts.{User, UserToken}
  alias Courier.Core.Audit

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

  @mcp_touch_interval_seconds 60

  def create_mcp_token(%User{} = user, name) when is_binary(name) do
    {raw, user_token} = UserToken.build_mcp_token(user, String.slice(name, 0, 100))
    user_token = Repo.insert!(user_token)
    Audit.record("mcp_token_created", user, %{"conexao" => user_token.name})
    {:ok, raw, user_token}
  end

  def fetch_user_by_mcp_token(token) do
    with {:ok, query} <- UserToken.verify_mcp_token_query(token),
         {%User{} = user, user_token} <- Repo.one(query) do
      {:ok, user, touch_mcp_token(user_token)}
    else
      _ -> :error
    end
  end

  defp touch_mcp_token(%UserToken{} = user_token) do
    now = DateTime.utc_now(:second)

    if is_nil(user_token.last_used_at) or
         DateTime.before?(
           user_token.last_used_at,
           DateTime.add(now, -@mcp_touch_interval_seconds)
         ) do
      Repo.update_all(from(t in UserToken, where: t.id == ^user_token.id),
        set: [last_used_at: now]
      )

      %{user_token | last_used_at: now}
    else
      user_token
    end
  end

  def list_mcp_tokens(%User{} = user) do
    user |> UserToken.mcp_tokens_by_user_query() |> Repo.all()
  end

  def revoke_mcp_token(%User{} = user, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %UserToken{} = user_token <-
           Repo.get_by(UserToken.mcp_tokens_by_user_query(user), id: uuid) do
      Repo.delete!(user_token)
      Audit.record("mcp_token_revoked", user, %{"conexao" => user_token.name})
      :ok
    else
      _ -> {:error, :not_found}
    end
  end
end
