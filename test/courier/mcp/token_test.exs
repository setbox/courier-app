defmodule Courier.MCP.TokenTest do
  use Courier.DataCase, async: true

  import Courier.Core.AccountsFixtures

  alias Courier.Core.Accounts
  alias Courier.Core.Accounts.UserToken
  alias Courier.Core.Audit.AuditLog

  test "the raw token is not stored and its creation is audited" do
    user = user_fixture()
    {:ok, raw, token} = Accounts.create_mcp_token(user, "Claude")

    refute token.token == Base.url_decode64!(raw, padding: false)
    assert {:ok, found, %UserToken{name: "Claude"}} = Accounts.fetch_user_by_mcp_token(raw)
    assert found.id == user.id
    assert Repo.get_by!(AuditLog, action: "mcp_token_created", actor_id: user.id)
  end

  test "refuses invalid tokens and a session token in place of an MCP token" do
    assert :error = Accounts.fetch_user_by_mcp_token("nao-existe")
    assert :error = Accounts.fetch_user_by_mcp_token(nil)

    session = Accounts.generate_user_session_token(user_fixture())
    assert :error = Accounts.fetch_user_by_mcp_token(Base.url_encode64(session, padding: false))
  end

  test "revoking reaches only the owner's connection" do
    owner = user_fixture()
    other = user_fixture()
    {:ok, raw, token} = Accounts.create_mcp_token(owner, "Claude")

    assert {:error, :not_found} = Accounts.revoke_mcp_token(other, token.id)
    assert {:error, :not_found} = Accounts.revoke_mcp_token(owner, "nao-e-uuid")
    assert :ok = Accounts.revoke_mcp_token(owner, token.id)
    assert :error = Accounts.fetch_user_by_mcp_token(raw)
    assert Repo.get_by!(AuditLog, action: "mcp_token_revoked", actor_id: owner.id)
  end
end
