defmodule Courier.MCP.Data do
  alias Courier.Core.Apps.{App, ChannelConfig, Environment}
  alias Courier.Core.Emails.{Email, Event, Recipient}
  alias Courier.Core.Webhooks.Delivery

  def app(%App{} = app) do
    %{
      id: app.id,
      nome: app.name,
      slug: app.slug,
      ambientes: Enum.map(List.wrap(loaded(app.environments)), &environment_row/1)
    }
  end

  def environment_row(%Environment{} = env) do
    %{id: env.id, nome: env.name, slug: env.slug, tem_token: not is_nil(env.client_token_hint)}
  end

  def environment(%Environment{} = env, config, unsubscribed) do
    %{
      id: env.id,
      aplicacao: env.app && %{id: env.app.id, nome: env.app.name},
      nome: env.name,
      slug: env.slug,
      token_gerado_em: env.client_token_generated_at,
      webhook_url: env.webhook_url,
      permitidos: env.allowed_recipients,
      bloqueados: env.blocked_recipients,
      descadastros_de_marketing: unsubscribed,
      email: email_config(config)
    }
  end

  defp email_config(nil), do: nil

  defp email_config(%ChannelConfig{} = config) do
    %{
      provider: config.provider,
      provider_nome: ChannelConfig.provider_label(config.provider),
      remetente: config.from_email,
      nome_do_remetente: config.from_name,
      message_stream: config.message_stream,
      pronto: ChannelConfig.ready?(config),
      webhook_do_provider_erro: ChannelConfig.webhook_error(config)
    }
  end

  def email_row(%Email{} = email) do
    %{
      id: email.id,
      status: email.status,
      categoria: email.category,
      provider: email.provider,
      assunto: email.subject,
      remetente: email.from,
      ambiente: environment_label(email.environment),
      destinatarios: Enum.map(List.wrap(loaded(email.recipients)), & &1.address),
      criado_em: email.inserted_at,
      enviado_em: email.sent_at,
      falhou_em: email.failed_at,
      erro: email.error_message
    }
  end

  def email(%Email{} = email, events, deliveries) do
    email
    |> email_row()
    |> Map.merge(%{
      responder_para: email.reply_to,
      tag: email.tag,
      metadata: email.metadata,
      provider_message_id: email.provider_message_id,
      tentativas: email.attempts,
      destinatarios: Enum.map(email.recipients, &recipient/1),
      eventos: Enum.map(events, &event/1),
      entregas_de_webhook: Enum.map(deliveries, &delivery/1)
    })
  end

  defp recipient(%Recipient{} = r) do
    %{
      endereco: r.address,
      tipo: r.kind,
      status: r.status,
      status_em: r.status_at,
      devolucao: r.bounce_kind,
      detalhe: r.detail,
      aberto_em: r.opened_at,
      clicado_em: r.clicked_at
    }
  end

  defp event(%Event{} = e) do
    %{tipo: e.type, em: e.occurred_at, destinatario: e.recipient && e.recipient.address}
  end

  defp delivery(%Delivery{} = d) do
    %{
      id: d.id,
      url: d.url,
      status: d.status,
      tentativas: d.attempts,
      resposta: d.response_status,
      erro: d.response_error,
      entregue_em: d.delivered_at,
      evento: d.email_event && d.email_event.type
    }
  end

  def failure(f) do
    %{
      tipo: f.type,
      em: f.at,
      email_id: f.email.id,
      assunto: f.email.subject,
      destinatario: f.address,
      ambiente: environment_label(f.email.environment),
      provider: f.email.provider,
      motivo: f.reason
    }
  end

  def environment_label(%Environment{app: %App{name: app}, name: name}), do: "#{app} / #{name}"
  def environment_label(_env), do: nil

  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(value), do: value
end
