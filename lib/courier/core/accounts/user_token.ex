defmodule Courier.Core.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias Courier.Core.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32
  @session_validity_in_days 14
  @mcp_context "mcp"

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    field :name, :string
    field :last_used_at, :utc_datetime
    belongs_to :user, Courier.Core.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  def build_mcp_token(user, name) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: :crypto.hash(@hash_algorithm, token),
       context: @mcp_context,
       name: name,
       user_id: user.id
     }}
  end

  def verify_mcp_token_query(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        {:ok,
         from(
           token in by_token_and_context_query(
             :crypto.hash(@hash_algorithm, decoded),
             @mcp_context
           ),
           join: user in assoc(token, :user),
           select: {user, token}
         )}

      :error ->
        :error
    end
  end

  def verify_mcp_token_query(_token), do: :error

  def mcp_tokens_by_user_query(user) do
    from t in UserToken,
      where: t.user_id == ^user.id and t.context == @mcp_context,
      order_by: [desc: t.inserted_at, desc: t.id]
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
