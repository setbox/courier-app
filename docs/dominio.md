# Domínio

## Entidades

| Entidade | Tabela | Módulo | O que é |
|---|---|---|---|
| Aplicação | `apps` | `Courier.Core.Apps.App` | Sistema cliente (Jayio, Punhado, PJ Park). Nome e slug únicos |
| Ambiente | `environments` | `Courier.Core.Apps.Environment` | Instância da aplicação (local, dev, prod...). Guarda o hash do token `cl_`, o webhook para o cliente e as listas `allowed_recipients` (whitelist) e `blocked_recipients` (blacklist) |
| Configuração de canal | `channel_configs` | `Courier.Core.Apps.ChannelConfig` | Uma por (ambiente, canal). Hoje só `email` com `postmark`: Server Token cifrado, remetente padrão, stream, rastreio e a credencial do webhook do Postmark |
| E-mail | `emails` | `Courier.Core.Emails.Email` | Um pedido aceito pela API. Metadados no banco; o corpo fica no MinIO em `body_key` |
| Destinatário | `email_recipients` | `Courier.Core.Emails.Recipient` | Cada endereço de `to`, `cc` e `bcc`, com status próprio |
| Evento | `email_events` | `Courier.Core.Emails.Event` | Linha do tempo do e-mail: recebido, enviado, falhou e os eventos do Postmark |
| Entrega de webhook | `webhook_deliveries` | `Courier.Core.Webhooks.Delivery` | Cada evento repassado ao cliente, com tentativas e última resposta |

Aplicação não é chamada de `Application` no código para não confundir com a aplicação OTP
(`Courier.Application`): o módulo é `App`, a tabela é `apps`.

## Estados

**E-mail** (`emails.status`):

| Status | Quando |
|---|---|
| `queued` | Aceito pela API, aguardando o worker |
| `sent` | O Postmark aceitou (`MessageID` em `provider_message_id`) |
| `failed` | Recusa permanente do Postmark, ou 10 tentativas transitórias esgotadas |

**Destinatário** (`email_recipients.status`): `pending` → `delivered` → `bounced` ou
`spam_complaint`. Uma entrega que chega depois de um bounce não desfaz o bounce. Abertura e clique não
mudam o status: ficam em `opened_at` e `clicked_at` (primeira vez) e em eventos.

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
   chama `Courier.Connectors.Postmark.send_email/2`.
   - `200`: `sent`, evento `sent`.
   - `401` ou `422`: `failed` na hora, com `ErrorCode` e mensagem do Postmark; o job é cancelado.
   - Outro status, timeout ou MinIO indisponível: nova tentativa com o backoff do Oban; na décima,
     `failed`.
3. **Eventos do Postmark** (`POST /webhooks/postmark/:environment_id`, Basic Auth do ambiente).
   `Courier.Core.Emails.apply_postmark_event/2` acha o e-mail pelo `MessageID` dentro do ambiente,
   atualiza o destinatário e grava o evento. Mensagem desconhecida ou tipo não tratado responde `200`
   e é ignorado, para o Postmark não reenviar em loop.
4. **Repasse ao cliente**. Todo evento (menos `queued`) de um ambiente com `webhook_url` vira uma
   `webhook_deliveries` e um job `Courier.Workers.DeliverWebhook` (fila `webhooks`, até 14
   tentativas, backoff de 20s dobrando até 4h, cerca de 24h no total). Só `2xx` conta como entregue.
5. **Retenção** (`Courier.Workers.PurgeExpired`, diário às 06:00 UTC). Apaga e-mails com mais de 90
   dias, com destinatários, eventos e entregas (cascade), e o corpo no MinIO.

## Tokens e segredos

| O quê | Formato | Guarda |
|---|---|---|
| Token do ambiente | `cl_` + 32 bytes aleatórios (base64url) | SHA-256 em `client_token_hash`, últimos 4 em `client_token_hint`. Mostrado uma vez |
| Segredo do webhook do cliente | `whsec_` + 32 bytes | Cifrado (`Courier.Vault`) em `environments.webhook_secret`. Mostrado uma vez |
| Server Token do Postmark | o do Postmark | Cifrado em `channel_configs.server_token`; a tela mostra só os últimos 4 |
| Senha do webhook do Postmark | 24 bytes aleatórios | Cifrada em `channel_configs.inbound_password`; visível na tela para cadastro manual. Usuário fixo `courier` |
