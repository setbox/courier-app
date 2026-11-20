defmodule Courier.MCP.Tools.RemoveUnsubscribe do
  @moduledoc """
  Tira um endereço da lista de descadastrados de marketing de um ambiente (a pessoa pediu para voltar a receber). Pede confirmação à pessoa, com o motivo. Sem formulário, pergunte o motivo e se ela confirma, e chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => true}

  alias Courier.Core.{Apps, Unsubscribes}
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :environment_id, :string, required: true
    field :address, :string, required: true
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
          address = MCP.arg(params, :address)

          MCP.write(frame, user, params, %{
            tool: "remove_unsubscribe",
            message:
              "VOLTAR A ENVIAR marketing para #{address} em #{Data.environment_label(env)}",
            run: fn -> env |> Unsubscribes.remove(address) |> MCP.ok(&%{reinscrito: &1}) end
          })
      end
    end)
  end
end
