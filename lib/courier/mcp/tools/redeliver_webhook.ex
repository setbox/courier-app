defmodule Courier.MCP.Tools.RedeliverWebhook do
  @moduledoc """
  Reenvia à aplicação o webhook de um evento (o id vem de entregas_de_webhook no get_email). Pede confirmação à pessoa, com o motivo. Sem formulário, pergunte o motivo e se ela confirma, e chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => false}

  alias Courier.Core.Webhooks
  alias Courier.MCP

  schema do
    field :delivery_id, :string, required: true
    field :reason, :string, description: "Motivo dado pela pessoa (sem formulário)"
    field :confirm, :boolean, description: "true depois que a pessoa confirmou (sem formulário)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn user ->
      delivery = Webhooks.get_delivery!(MCP.arg(params, :delivery_id))

      MCP.write(frame, user, params, %{
        tool: "redeliver_webhook",
        message: "REENVIAR o webhook #{delivery.email_event.type} para #{delivery.url}",
        run: fn ->
          delivery |> Webhooks.redeliver() |> MCP.ok(&%{entrega_id: &1.id, status: &1.status})
        end
      })
    end)
  end
end
