defmodule Courier.MCP.TokenValidator do
  @behaviour Anubis.Server.Authorization.Validator

  alias Courier.Core.Accounts

  @impl true
  def validate_token(token, config) do
    case Accounts.fetch_user_by_mcp_token(token) do
      {:ok, user, user_token} ->
        {:ok,
         %{
           "sub" => user.id,
           "aud" => config.resource,
           "scopes" => [Courier.OAuth.scope()],
           "connection" => user_token.name
         }}

      :error ->
        {:error, :token_not_found}
    end
  end
end
