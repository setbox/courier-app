defmodule Courier.MCP.Tools.SearchAudit do
  @moduledoc """
  Auditoria: ações feitas pelo MCP (com ferramenta, motivo e parâmetros) e conexões MCP autorizadas ou revogadas. Da mais recente para a mais antiga.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.Audit
  alias Courier.MCP

  schema do
    field :action, :string, description: "mcp_write, mcp_token_created ou mcp_token_revoked"
    field :actor, :string, description: "Parte do e-mail de quem fez"
    field :limit, :integer, description: "Até 200 (padrão 50)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn _user ->
      logs =
        %{action: MCP.arg(params, :action), actor: MCP.arg(params, :actor)}
        |> Audit.list(MCP.page(params))
        |> Enum.map(
          &%{acao: &1.action, quem: &1.actor_email, em: &1.inserted_at, detalhes: &1.metadata}
        )

      MCP.reply(frame, %{registros: logs})
    end)
  end
end
