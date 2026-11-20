defmodule Courier.Core.Audit do
  import Ecto.Query, warn: false

  alias Courier.Core.Accounts.User
  alias Courier.Core.Audit.AuditLog
  alias Courier.Repo

  @actions %{
    "mcp_write" => "Ação pelo MCP",
    "mcp_token_created" => "Conexão MCP autorizada",
    "mcp_token_revoked" => "Conexão MCP revogada"
  }

  def action_label(action), do: Map.get(@actions, action, action)

  def record(action, %User{} = actor, metadata \\ %{}) when is_binary(action) do
    Repo.insert!(%AuditLog{
      action: action,
      actor_id: actor.id,
      actor_email: actor.email,
      metadata: metadata
    })
  end

  def list(filters \\ %{}, limit \\ 100) do
    from(a in AuditLog, order_by: [desc: a.inserted_at, desc: a.id], limit: ^limit)
    |> filter(filters)
    |> Repo.all()
  end

  defp filter(query, filters) do
    Enum.reduce(filters, query, fn
      {:action, action}, q when is_binary(action) and action != "" ->
        where(q, [a], a.action == ^action)

      {:actor, email}, q when is_binary(email) and email != "" ->
        where(q, [a], ilike(a.actor_email, ^"%#{email}%"))

      {:since, %DateTime{} = since}, q ->
        where(q, [a], a.inserted_at >= ^since)

      _, q ->
        q
    end)
  end
end
