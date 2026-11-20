defmodule Courier.MCP.Tools.ConfigureWebhook do
  @moduledoc """
  Configura o webhook de um ambiente: a URL da aplicação que recebe os eventos e quais tipos vão para ela (sent, failed, delivery, not_found, bounce, spam_complaint, open, click, subscription_change). Cada evento chega por POST assinado no header Courier-Signature. Na primeira vez que o ambiente ganha URL, a resposta traz o segredo de assinatura (whsec_...), só desta vez: entregue à pessoa ou grave onde ela pediu, sem repetir depois. Lista de eventos vazia faz o webhook não mandar nada. Pede confirmação à pessoa, com o motivo. Sem formulário, pergunte o motivo e se ela confirma, e chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => true}

  alias Courier.Core.{Apps, Webhooks}
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :environment_id, :string, required: true
    field :url, :string, required: true, description: "URL http ou https da aplicação"
    field :events, {:list, :string}, required: true, description: "Tipos de evento enviados"
    field :reason, :string, description: "Motivo dado pela pessoa (sem formulário)"
    field :confirm, :boolean, description: "true depois que a pessoa confirmou (sem formulário)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn user ->
      events = MCP.arg(params, :events) || []
      valid = Enum.map(Webhooks.event_types(), &Atom.to_string/1)

      env = Apps.get_environment(MCP.arg(params, :environment_id))

      cond do
        Enum.any?(events, &(&1 not in valid)) ->
          MCP.error(frame, "Evento inválido. Use: #{Enum.join(valid, ", ")}.")

        is_nil(env) ->
          MCP.error(frame, "Ambiente não encontrado.")

        true ->
          write(frame, user, params, env, events)
      end
    end)
  end

  defp write(frame, user, params, env, events) do
    url = MCP.arg(params, :url)

    MCP.write(frame, user, params, %{
      tool: "configure_webhook",
      message:
        "CONFIGURAR o webhook de #{Data.environment_label(env)} para #{url} com os eventos #{Enum.join(events, ", ")}",
      run: fn ->
        case Apps.update_webhook(env, %{"webhook_url" => url, "webhook_events" => events}) do
          {:ok, env, secret} ->
            {:ok,
             MCP.present(%{
               webhook_url: env.webhook_url,
               eventos: env.webhook_events,
               segredo: secret
             })}

          {:error, changeset} ->
            {:error, changeset}
        end
      end
    })
  end
end
