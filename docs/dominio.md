# Domínio

## Entidades

| Entidade | Tabela | Módulo | O que é |
|---|---|---|---|
| Aplicação | `apps` | `Courier.Core.Apps.App` | Sistema cliente (Jayio, Punhado, PJ Park). Nome e slug únicos |
| Ambiente | `environments` | `Courier.Core.Apps.Environment` | Instância da aplicação (local, dev, prod...). Guarda o hash do token `cl_`, o webhook para o cliente (`webhook_url`, `webhook_secret` e `webhook_events`, os tipos repassados) e as listas `allowed_recipients` (whitelist) e `blocked_recipients` (blacklist) |
| Configuração de canal | `channel_configs` | `Courier.Core.Apps.ChannelConfig` | Uma por (ambiente, canal). Hoje só `email`, com `postmark` (Server Token cifrado, remetente padrão, stream, rastreio e a credencial do webhook do Postmark) `brevo` (API Key cifrada, remetente padrão, `brevo_webhook_id` e a mesma credencial de webhook) ou `sandbox` (só o remetente padrão: o Courier guarda o e-mail e não envia) |
| E-mail | `emails` | `Courier.Core.Emails.Email` | Um pedido aceito pela API. Metadados no banco; o corpo fica no MinIO em `body_key`. `category` (`transactional` ou `marketing`, obrigatória) e `provider` (gravado ao enviar ou falhar) |
| Descadastro | `email_suppressions` | `Courier.Core.Unsubscribes.Suppression` | Endereço que cancelou a inscrição de marketing num ambiente (`Courier.Core.Unsubscribes`). Bloqueia só `marketing` |
| Estatística diária | `email_daily_stats` | `Courier.Core.Stats.DailyStat` | Contadores por dia, ambiente, provider e categoria (enviados, entregues, com erro, não encontrado, devolvidos, spam). Sobrevivem à retenção; base do Painel (`Courier.Core.Stats`) |
| Destinatário | `email_recipients` | `Courier.Core.Emails.Recipient` | Cada endereço de `to`, `cc` e `bcc`, com status próprio |
| Evento | `email_events` | `Courier.Core.Emails.Event` | Linha do tempo do e-mail: recebido, enviado, falhou e, no Postmark, os eventos de entrega |
| Entrega de webhook | `webhook_deliveries` | `Courier.Core.Webhooks.Delivery` | Cada evento repassado ao cliente, com tentativas e última resposta |

Aplicação não é chamada de `Application` no código para não confundir com a aplicação OTP
(`Courier.Application`): o módulo é `App`, a tabela é `apps`.

## Estados

**E-mail** (`emails.status`):

| Status | Quando |
|---|---|
| `queued` | Aceito pela API, aguardando o worker |
| `sent` | O provider aceitou (`MessageID` do Postmark, `messageId` do Brevo sem `<>` ou `sandbox-<uuid>` no sandbox, em `provider_message_id`) |
| `failed` | Recusa permanente do provider, ou 10 tentativas transitórias esgotadas |

**Destinatário** (`email_recipients.status`): `pending` → `delivered` → `bounced` ou
`spam_complaint`. Uma entrega que chega depois de um bounce não desfaz o bounce. Abertura e clique não
mudam o status: ficam em `opened_at` e `clicked_at` (primeira vez) e em eventos. No sandbox
não há eventos de entrega, então o destinatário fica em `pending`. Uma devolução guarda `bounce_kind`: `not_found` (endereço inexistente) ou `other`.

**Evento** (`email_events.type`): `queued`, `sent`, `failed`, `delivery`, `bounce`,
`spam_complaint`, `open`, `click`, `subscription_change`.

**Entrega de webhook** (`webhook_deliveries.status`): `pending` → `delivered` ou `failed`.

## Fluxo de um e-mail

1. **Entrada** (`POST /api/v1/emails`). `CourierWeb.Plugs.ClientAuth` acha o ambiente pelo hash do
   `Api-Key`. `Courier.Core.Emails.submit/3`:
   - recusa com `provider_not_configured` se o ambiente não tem Server Token ou remetente;
   - valida o pedido (`Courier.Core.Emails.Request`);
   - recusa com `recipient_not_allowed` se algum destinatário (`to`, `cc` ou `bcc`) estiver fora da
     whitelist ou dentro da blacklist do ambiente (`Environment.recipient_allowed?/2`);
   - com `Idempotency-Key`, trava a chave (`pg_advisory_xact_lock`) e devolve o e-mail existente se
     houver um nas últimas 24 horas;
   - grava o corpo no MinIO (`Courier.Core.Storage`), depois o e-mail, os destinatários, o evento
     `queued` e o job `Courier.Workers.SendEmail`, numa transação. Se o MinIO falhar, responde
     `storage_unavailable`.
2. **Envio** (`Courier.Workers.SendEmail`, fila `emails`, até 10 tentativas). Lê o corpo do MinIO e
   chama o provider do ambiente (`provider` da configuração de canal):
   - **Postmark**: `Courier.Connectors.Postmark.send_email/2`, `POST /email`. `401` ou `422`:
     `failed` na hora, com `ErrorCode` e mensagem do Postmark.
   - **Brevo**: `Courier.Connectors.Brevo.send_email/2`, `POST https://api.brevo.com/v3/smtp/email`
     com `api-key`. `201`: aceito. `400` a `403`: `failed` na hora, com `code: message` do Brevo.
   - **Sandbox do Courier**: não chama ninguém. Lido o corpo, o e-mail vai para `sent` com
     `provider_message_id` `sandbox-<uuid>` (`Courier.Core.Emails.sandbox?/1`).

   Em todos:
   - Aceito (`200` ou, no Brevo, `201`): `sent`, evento `sent`.
   - Recusa permanente: o job é cancelado.
   - Outro status, timeout ou MinIO indisponível: nova tentativa com o backoff do Oban; na décima,
     `failed`.
3. **Eventos do Postmark** (`POST /webhooks/postmark/:environment_id`, Basic Auth do ambiente) e
   **do Brevo** (`POST /webhooks/brevo/:environment_id`, mesma credencial, aplicados por
   `Courier.Core.Emails.apply_brevo_event/2`: `delivered` → entrega; `hard_bounce`, `blocked`,
   `invalid_email` → bounce; `spam`; `opened`; `click`; `unsubscribed`; o resto é ignorado). O
   sandbox não gera eventos.
   `Courier.Core.Emails.apply_postmark_event/2` acha o e-mail pelo `MessageID` dentro do ambiente,
   atualiza o destinatário e grava o evento. Mensagem desconhecida ou tipo não tratado responde `200`
   e é ignorado, para o Postmark não reenviar em loop.
4. **Repasse ao cliente**. Todo evento de tipo marcado em `webhook_events`, num ambiente com `webhook_url`, vira uma
   `webhook_deliveries` e um job `Courier.Workers.DeliverWebhook` (fila `webhooks`, até 14
   tentativas, backoff de 20s dobrando até 4h, cerca de 24h no total). Só `2xx` conta como entregue.
5. **Retenção** (`Courier.Workers.PurgeExpired`, diário às 06:00 UTC). Apaga e-mails com mais de 90
   dias, com destinatários, eventos e entregas (cascade), e o corpo no MinIO.

## Tokens e segredos

| O quê | Formato | Guarda |
|---|---|---|
| Token do ambiente | `cl_` + 32 bytes aleatórios (base64url) | SHA-256 em `client_token_hash`, últimos 4 em `client_token_hint`. Mostrado uma vez |
| Segredo do webhook do cliente | `whsec_` + 32 bytes | Cifrado (`Courier.Vault`) em `environments.webhook_secret`. Mostrado uma vez |
| Server Token do Postmark ou API Key do Brevo | o do provider | Cifrado em `channel_configs.server_token`; a tela mostra só os últimos 4 |
| Senha do webhook do Postmark e do Brevo | 24 bytes aleatórios | Cifrada em `channel_configs.inbound_password`; visível na tela para cadastro manual. Usuário fixo `courier` |
