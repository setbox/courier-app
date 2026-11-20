defmodule Courier.MCP.Tools.UpdateRecipientLists do
  @moduledoc """
  Troca as listas de destinatários de um ambiente: permitidos (com a lista preenchida, só ela recebe) e bloqueados (nunca recebem). Cada item é um e-mail ou um domínio começando com @. Uma lista omitida fica como está; lista vazia limpa. Pede confirmação à pessoa, com o motivo. Sem formulário, pergunte o motivo e se ela confirma, e chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => true}

  alias Courier.Core.Apps
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :environment_id, :string, required: true
    field :allowed, {:list, :string}, description: "Permitidos: e-mails ou @dominio"
    field :blocked, {:list, :string}, description: "Bloqueados: e-mails ou @dominio"
    field :reason, :string, description: "Motivo dado pela pessoa (sem formulário)"
    field :confirm, :boolean, description: "true depois que a pessoa confirmou (sem formulário)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn user ->
      case Apps.get_environment(MCP.arg(params, :environment_id)) do
        nil ->
          MCP.error(frame, "Ambiente não encontrado.")

        env ->
          allowed = MCP.arg(params, :allowed) || env.allowed_recipients
          blocked = MCP.arg(params, :blocked) || env.blocked_recipients

          MCP.write(frame, user, params, %{
            tool: "update_recipient_lists",
            message:
              "TROCAR as listas de #{Data.environment_label(env)}: permitidos #{inspect(allowed)}, bloqueados #{inspect(blocked)}",
            run: fn ->
              env
              |> Apps.update_recipient_lists(%{
                "allowed_recipients" => Enum.join(allowed, "\n"),
                "blocked_recipients" => Enum.join(blocked, "\n")
              })
              |> MCP.ok(&%{permitidos: &1.allowed_recipients, bloqueados: &1.blocked_recipients})
            end
          })
      end
    end)
  end
end
