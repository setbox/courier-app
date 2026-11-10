# API

Base: `https://courier.setbox.com.br/api/v1`. Corpo e respostas em JSON, campos em `snake_case` e
em inglês.

## Autenticação

Header `Api-Key` com o token `cl_` do ambiente, gerado na tela do ambiente. Ele identifica aplicação e
ambiente: o pedido não informa nenhum dos dois. Sem token ou com token inválido:

```http
HTTP/1.1 401
{"error": {"code": "invalid_api_key", "message": "Missing or invalid Api-Key header"}}
```

## Erros

Todo erro tem a forma `{"error": {"code": "...", "message": "...", "details": {...}}}`. O `code` é
estável; a mensagem pode mudar.

| HTTP | `code` | Quando |
|---|---|---|
| 401 | `invalid_api_key` | Token ausente ou inválido |
| 404 | `not_found` | E-mail não existe neste ambiente |
| 422 | `invalid_request` | Campo inválido; `details` traz a lista por campo |
| 422 | `provider_not_configured` | O ambiente não tem Server Token do Postmark ou remetente |
| 422 | `recipient_not_allowed` | Algum destinatário está fora da whitelist ou na blacklist do ambiente; `details.recipients` lista os barrados. O pedido inteiro é recusado |
| 503 | `storage_unavailable` | O corpo não pôde ser gravado; tente de novo com a mesma `Idempotency-Key` |

## Enviar e-mail

`POST /emails`

| Campo | Tipo | Obrigatório | Observação |
|---|---|---|---|
| `to` | lista de e-mails (ou um texto) | sim | Endereço simples, sem nome |
| `subject` | texto | sim | Até 2000 caracteres |
| `html_body` | texto | um dos dois | |
| `text_body` | texto | um dos dois | |
| `cc`, `bcc` | lista de e-mails | não | Máximo de 50 destinatários somando `to`, `cc` e `bcc` |
| `from` | texto | não | `email@dominio` ou `Nome <email@dominio>`. Padrão: o da configuração. Precisa estar verificado no Postmark |
| `reply_to` | texto | não | |
| `tag` | texto | não | Tag do Postmark |
| `message_stream` | texto | não | Padrão: o da configuração (`outbound`) |
| `metadata` | objeto | não | Até 50 chaves, valores simples, 8 KB. Volta nas consultas e nos webhooks |
| `track_opens`, `track_links` | booleano | não | Padrão: o da configuração |

Header opcional `Idempotency-Key`: a mesma chave no mesmo ambiente em 24 horas devolve o e-mail
original, sem reenviar, com `Idempotent-Replayed: true`.

```http
POST /api/v1/emails
Api-Key: cl_...
Idempotency-Key: pedido-123-boas-vindas

{
  "to": ["ana@exemplo.com.br"],
  "subject": "Bem-vinda",
  "html_body": "<p>Olá, Ana</p>",
  "metadata": {"order_id": "123"}
}
```

```http
HTTP/1.1 202
Idempotent-Replayed: false

{"id": "fa47cfd7-343e-4352-8c16-8b38bcb3c4ac", "status": "queued"}
```

`202` quer dizer aceito e guardado; o envio acontece em seguida, pela fila.

O Courier envia só e-mail transacional: não acrescenta link de descadastro.

```http
HTTP/1.1 422

{"error": {"code": "recipient_not_allowed",
           "message": "Some recipients are not allowed in this environment",
           "details": {"recipients": ["bruno@fora.com.br"]}}}
```

## Consultar

`GET /emails/:id`

```json
{
  "id": "fa47cfd7-...",
  "status": "sent",
  "from": "Exemplo <naoresponda@exemplo.com.br>",
  "subject": "Bem-vinda",
  "metadata": {"order_id": "123"},
  "idempotency_key": "pedido-123-boas-vindas",
  "provider_message_id": "b7bc2f4a-...",
  "error": null,
  "attempts": 1,
  "created_at": "2026-11-10T13:52:13.123456Z",
  "sent_at": "2026-11-10T13:52:14Z",
  "failed_at": null,
  "recipients": [
    {"address": "ana@exemplo.com.br", "kind": "to", "status": "delivered",
     "status_at": "2026-11-10T13:52:20Z", "detail": null, "opened_at": null, "clicked_at": null}
  ]
}
```

`GET /emails` lista os e-mails do ambiente, mais recentes primeiro.

| Parâmetro | Exemplo |
|---|---|
| `status` | `queued`, `sent`, `failed` |
| `to` | `ana@exemplo.com.br` (qualquer destinatário) |
| `from_date`, `to_date` | `2026-11-10` ou ISO 8601 completo |
| `metadata[chave]` | `metadata[order_id]=123` |
| `idempotency_key` | `pedido-123-boas-vindas` |
| `limit` | 1 a 100, padrão 50 |
| `cursor` | o `next_cursor` da página anterior |

Resposta: `{"data": [...], "next_cursor": "..."}`; `next_cursor` nulo na última página.

`GET /emails/:id/events` devolve a linha do tempo:
`{"data": [{"id", "type", "occurred_at", "recipient", "data"}]}`.

## Webhook para a aplicação

Configurado na tela do ambiente. A cada evento o Courier faz `POST` na URL:

```http
POST https://app.exemplo.com.br/webhooks/courier
Content-Type: application/json
Courier-Event-Id: 77a3f8a4-...
Courier-Signature: t=1762782734,v1=5f1c...

{
  "id": "77a3f8a4-...",
  "type": "email.delivery",
  "occurred_at": "2026-11-10T13:52:20Z",
  "email": {"id": "fa47cfd7-...", "status": "sent", "subject": "Bem-vinda",
            "metadata": {"order_id": "123"}, "idempotency_key": "pedido-123-boas-vindas"},
  "recipient": "ana@exemplo.com.br",
  "data": {"RecordType": "Delivery", "...": "payload do Postmark"}
}
```

Tipos: `email.sent`, `email.failed`, `email.delivery`, `email.bounce`, `email.spam_complaint`,
`email.open`, `email.click`, `email.subscription_change`.

**Validar a assinatura**: `v1` é o HMAC-SHA256, em hexadecimal minúsculo, de
`"<t>.<corpo bruto>"` com o segredo `whsec_...` do ambiente. Recuse se não conferir ou se `t` estiver
muito longe do relógio (5 minutos, por exemplo). Use o `Courier-Event-Id` para descartar repetidos:
a mesma entrega pode chegar mais de uma vez.

Responda `2xx` para confirmar. Qualquer outro status, ou mais de 10 segundos sem resposta, faz o
Courier tentar de novo, com intervalo crescente, por cerca de 24 horas.
