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
| 422 | `provider_not_configured` | O ambiente não tem remetente ou, no Postmark e no Brevo, token do provider |
| 422 | `recipient_not_allowed` | Algum destinatário está fora da whitelist ou na blacklist do ambiente; `details.recipients` lista os barrados. O pedido inteiro é recusado |
| 422 | `recipient_unsubscribed` | E-mail de `marketing` para quem cancelou a inscrição neste ambiente; `details.recipients` lista os endereços |
| 503 | `storage_unavailable` | O corpo não pôde ser gravado; tente de novo com a mesma `Idempotency-Key` |

## Enviar e-mail

`POST /emails`

| Campo | Tipo | Obrigatório | Observação |
|---|---|---|---|
| `category` | `transactional` ou `marketing` | sim | Sem ela, `422` com `invalid_request`. No Postmark, `marketing` usa o stream `broadcast` quando o pedido não informa `message_stream` |
| `to` | lista de e-mails (ou um texto) | sim | Endereço simples, sem nome |
| `subject` | texto | sim | Até 2000 caracteres |
| `html_body` | texto | um dos dois | |
| `text_body` | texto | um dos dois | |
| `cc`, `bcc` | lista de e-mails | não | Máximo de 50 destinatários somando `to`, `cc` e `bcc` |
| `from` | texto | não | `email@dominio` ou `Nome <email@dominio>`. Padrão: o da configuração. No Postmark, precisa estar verificado |
| `reply_to` | texto | não | |
| `tag` | texto | não | Tag do Postmark ou `tags` do Brevo |
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

Num ambiente com Brevo, `metadata`, `message_stream`, `track_opens` e `track_links` não vão ao
provider (o rastreio é da conta do Brevo); os eventos chegam como no Postmark.

Num ambiente com o Sandbox do Courier o e-mail não sai do Courier: fica guardado, com o conteúdo
visível na tela de E-mails, e não chega ao destinatário. A resposta e o fluxo são os mesmos
(`202`, depois `sent`), com `provider_message_id` começando por `sandbox-`; não há eventos de entrega.

**Marketing** vai para um destinatário só (um `to`, sem `cc` nem `bcc`). O Courier gera o descadastro:

- cabeçalhos `List-Unsubscribe: <https://<host>/u/<token>>` e `List-Unsubscribe-Post:
  List-Unsubscribe=One-Click` (descadastro em um clique do Gmail e do Yahoo);
- o link no corpo: onde o HTML ou o texto tiver `{{courier_unsubscribe_url}}`, entra a URL; sem o marcador,
  o Courier acrescenta uma linha no fim ("Para não receber mais estes e-mails, cancele a inscrição").

Quem cancela a inscrição deixa de receber marketing daquele ambiente (`recipient_unsubscribed`), e a
aplicação recebe o evento `email.subscription_change`. Transacional continua chegando.

**Transacional pelo Brevo** também leva os dois cabeçalhos do Courier (para o primeiro `to`), sem link
no corpo: sem eles, o Brevo põe o próprio `List-Unsubscribe`, e um clique ali bloqueia o endereço para
todo transacional da conta. Com o do Courier, o clique só tira a pessoa do marketing e gera
`email.subscription_change` (com `email.category` `transactional`). Pelo Postmark, transacional vai sem
esses cabeçalhos.

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
  "category": "transactional",
  "provider": "postmark",
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
  "email": {"id": "fa47cfd7-...", "status": "sent", "category": "transactional", "subject": "Bem-vinda",
            "metadata": {"order_id": "123"}, "idempotency_key": "pedido-123-boas-vindas"},
  "recipient": "ana@exemplo.com.br",
  "data": {"RecordType": "Delivery", "...": "payload do Postmark"}
}
```

Tipos: `email.sent`, `email.failed`, `email.delivery`, `email.not_found` (endereço inexistente, hard
bounce), `email.bounce` (as outras devoluções), `email.spam_complaint`, `email.open`, `email.click`,
`email.subscription_change`. **Só chegam os tipos marcados no ambiente**: um webhook novo nasce sem
nenhum, e a escolha é feita na tela do webhook ou pela ferramenta `configure_webhook` do MCP. Num
ambiente com o Sandbox do Courier só existem `email.sent` e `email.failed`, gerados pelo próprio Courier.

**Validar a assinatura**: `v1` é o HMAC-SHA256, em hexadecimal minúsculo, de
`"<t>.<corpo bruto>"` com o segredo `whsec_...` do ambiente. Recuse se não conferir ou se `t` estiver
muito longe do relógio (5 minutos, por exemplo). Use o `Courier-Event-Id` para descartar repetidos:
a mesma entrega pode chegar mais de uma vez.

Responda `2xx` para confirmar. Qualquer outro status, ou mais de 10 segundos sem resposta, faz o
Courier tentar de novo, com intervalo crescente, por cerca de 24 horas.
