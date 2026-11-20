# Decisões

Sabatina de 2026-11-10, que fechou o desenho da primeira entrega do envio de e-mail.

## Escopo e acesso

- **Sistema apartado da base do Obsidian.** O desenho anterior (template, regra, envelope, token no
  corpo) fica suspenso; a documentação vive aqui até o realinhamento.
- **Ferramenta só da Setbox.** Não existe organização nem tenant: todo usuário vê e configura todas as
  aplicações.
- **Sem cadastro público.** Usuário só nasce pelo seed por enquanto; gestão de usuários (convite,
  desativação) fica para depois.

## Aplicação, ambiente e configuração

- **Aplicação → ambientes.** Aplicação é o sistema cliente (Jayio, Punhado, PJ Park). Ambiente tem
  **nome livre** (local, dev, stage, prod, homolog...), com slug único dentro da aplicação. Nenhuma
  regra do sistema olha o nome.
- **Uma configuração por (ambiente, canal).** O ambiente pode ter e-mail hoje e SMS amanhã, cada canal
  com um provider. Na primeira entrega só existe e-mail → Postmark.
- **Mailtrap Sandbox como segundo provider de e-mail** (2026-11-10), substituído em 2026-11-20 pelo
  Sandbox do Courier (abaixo).
- **Sandbox do Courier no lugar do Mailtrap** (2026-11-20). O próprio Courier é o provider de teste
  (local, dev, stage): guarda o e-mail, mostra o conteúdo na tela de E-mails e não envia a ninguém.
  Não precisa de credencial, só de remetente. O e-mail vai a `sent` com `provider_message_id`
  `sandbox-<uuid>`, sem eventos de entrega. As configurações que usavam o Mailtrap viraram sandbox
  na migration. O que o Mailtrap fazia e o sandbox não faz (análise de spam e de HTML, SMTP, caixa
  compartilhada) ficou em issues. Trocar de provider para Postmark ou Brevo exige informar o token.
- **Brevo como terceiro provider de e-mail** (2026-11-19). Envio por `POST /v3/smtp/email` com
  `api-key` e eventos por webhook transacional cadastrado ao salvar, como no Postmark. O Brevo só
  documenta autenticação por credencial na URL, então o Courier põe `courier:<senha>` na URL e
  confere com o mesmo Basic Auth do Postmark. O `messageId` vem com `<>` e os eventos às vezes sem:
  o Courier guarda sem os sinais. `soft_bounce` e `deferred` são ignorados (o Brevo tenta de novo);
  `hard_bounce`, `blocked` e `invalid_email` viram bounce. Respostas `400` a `403` falham na hora;
  o resto é transitório.
- **Menu Providers é só visão** (2026-11-19): lista os providers e os ambientes que usam cada um.
  A credencial continua por ambiente; não há conta de provider compartilhada.
- **Credencial do provider cifrada com Cloak** (`Courier.Vault`, chave em `CLOAK_KEY`). A tela mostra
  só os últimos caracteres.
- **Remetente padrão na configuração**, com `from` opcional no pedido. Se o provider recusar
  (no Postmark, assinatura não verificada), o envio falha com o erro dele registrado.
- **Rastreio de abertura e clique** ligado ou desligado na configuração (padrão desligado), com
  `track_opens`/`track_links` opcionais no pedido.

## Tokens

- **`cl_`**: token do ambiente, para enviar e consultar. Um por ambiente; regenerar invalida o
  anterior na hora.
- **`pat_`**: token pessoal do usuário, global, para configuração por API. **Adiado**: a configuração
  só existe pela tela nesta entrega.
- **Hash, mostrado uma vez.** 32 bytes aleatórios depois do prefixo; o banco guarda o SHA-256 e os
  quatro últimos caracteres. Perdeu, regenera.
- Header da API: **`Api-Key`**.

## Pedido e resposta

- **Conteúdo vem pronto do cliente.** Obrigatórios: `to` (lista), `subject`, `html_body` e/ou
  `text_body`. Opcionais: `from`, `cc`, `bcc`, `reply_to`, `metadata`, `tag`, `message_stream`,
  `track_opens`, `track_links`. **Sem anexo.**
- **Vários destinatários, um envio.** O Postmark recebe um e-mail com todos; o Courier guarda status
  geral do e-mail e status por destinatário, porque os eventos do Postmark chegam por destinatário.
- **202 com validação antes.** Erro de token, de campo ou de configuração responde 4xx com código
  legível na hora. Aceito, responde `202` com `id` e `status: "queued"`.
- **`Idempotency-Key` opcional.** Mesma chave no mesmo ambiente em 24 horas devolve o pedido original
  sem reenviar.

## Envio e eventos

- **Oban envia.** Recusa permanente do Postmark (422, credencial inválida) marca `failed` na hora;
  erro transitório (5xx, 429, timeout) tenta até 10 vezes com backoff e depois marca `failed`.
- **Todos os eventos do Postmark** entram: Delivery, Bounce, SpamComplaint, Open, Click e
  SubscriptionChange.
- **Webhook do Postmark por ambiente**, com Basic Auth própria. O Courier cadastra sozinho pela API do
  Postmark ao salvar a configuração, e a tela mostra a URL e a credencial para cadastro manual.
- **Webhook para o cliente** por ambiente, assinado com HMAC-SHA256 (`Courier-Signature`). Só `2xx`
  conta como entregue; senão retenta com backoff por cerca de 24 horas. A tela mostra cada entrega e
  permite reenviar.

## Destinatários permitidos e bloqueados (2026-11-10)

- **Cada ambiente tem whitelist e blacklist** de destinatários, editadas na tela do ambiente.
- **Entrada**: e-mail exato (`ana@exemplo.com.br`) ou domínio inteiro (`@setbox.com.br`), sem
  diferenciar maiúsculas. Domínio não cobre subdomínio. Sem curinga.
- **Whitelist preenchida**: só endereços dela recebem. **Blacklist preenchida**: os dela não
  recebem, mesmo que estejam na whitelist.
- Vale para `to`, `cc` e `bcc`.
- **Um destinatário barrado recusa o pedido inteiro** (`422 recipient_not_allowed`, com os endereços
  em `details.recipients`). Nada é gravado nem enviado: o cliente decide o que fazer, e nunca sai um
  e-mail "pela metade" citando quem não recebeu.

## Categoria do e-mail (2026-11-20)

- **Todo e-mail tem categoria obrigatória: `transactional` ou `marketing`** (substitui o "só
  transacional" de 2026-11-10). Pedido sem ela é recusado com `422`. Os e-mails anteriores viraram
  `transactional` na migration.
- **Marketing no Postmark vai pelo stream `broadcast`** quando o pedido não informa `message_stream`:
  stream transacional não pode levar marketing. O server do Postmark precisa ter esse stream.
- **O Courier gera o descadastro do marketing**: link assinado por destinatário (`Phoenix.Token`, 2
  anos), cabeçalhos `List-Unsubscribe` e `List-Unsubscribe-Post` e o link no corpo (marcador
  `{{courier_unsubscribe_url}}` ou uma linha no fim). Por isso marketing tem um destinatário por
  e-mail. A página `/u/<token>` pede confirmação (um robô que abre links não descadastra); o POST,
  inclusive o de um clique sem CSRF, grava em `email_suppressions` e gera `email.subscription_change`.
  Marketing para quem saiu é recusado com `recipient_unsubscribed`; transacional segue.

## Painel e falhas (2026-11-20)

- **Contadores diários em `email_daily_stats`**, por dia (horário de Brasília), ambiente, provider e
  categoria: enviados, entregues, com erro, não encontrado, devolvidos e spam. O e-mail some em 90
  dias, o contador fica, e por isso o Painel mostra 12 meses. `Courier.Workers.RebuildStats` recalcula
  de hora em hora os 7 dias fechados (90 na primeira vez); o dia de hoje é calculado na hora.
- **Não encontrado** é a devolução por endereço inexistente: `HardBounce` e `BadEmailAddress` no
  Postmark, `hard_bounce` e `invalid_email` no Brevo (`email_recipients.bounce_kind = not_found`). O
  resto da devolução é "devolvido".
- **O e-mail guarda o provider** que o enviou ou recusou (`emails.provider`), para o gráfico por provider
  não mudar quando o ambiente troca de provider.
- **Falhas** é tela própria (`/falhas`): e-mails recusados pelo provider e destinatários devolvidos ou
  que marcaram spam, dentro da retenção de 90 dias.

## Consulta e retenção

- **Consultas**: por id, lista com filtros (status, destinatário, período, metadata,
  `Idempotency-Key`) e linha do tempo de eventos.
- **Retenção de 90 dias** para tudo. Metadados no Postgres; **corpo no MinIO**, gravado **antes** do
  202. MinIO fora do ar faz a API responder `503`, e o cliente retenta com a mesma `Idempotency-Key`.

## Acesso (2026-11-20)

- **Só conta Google.** Saíram o login por e-mail e senha, a confirmação por e-mail, a redefinição de
  senha e a tela de conta. A coluna `users.hashed_password` foi removida e os tokens de e-mail
  apagados; ficam só os tokens de sessão. O Google só confirma o e-mail de conta que já existe, então
  o administrador do seed é a porta de entrada. Dev usa o mesmo client OAuth da produção.

## MCP (2026-11-20)

- **MCP em `/mcp`, igual ao do PJ Park**: `anubis_mcp` com transporte HTTP e OAuth próprio (registro
  dinâmico de cliente, PKCE S256, tela de consentimento em `/oauth/authorize`, token por usuário em
  `users_tokens` com contexto `mcp`). Todo usuário do Courier pode autorizar; a conexão é revogada em
  "Acesso pelo MCP", no menu da conta.
- **Ferramentas de consulta**: `get_dashboard`, `list_failures`, `list_emails`, `get_email`, `list_apps`,
  `get_app`, `get_environment`, `list_providers`, `list_unsubscribes`, `search_audit`.
- **Ações com confirmação e motivo** (formulário do cliente MCP, ou `reason` e `confirm: true`):
  `send_test_email`, `redeliver_webhook`, `create_app`, `create_environment`, `update_recipient_lists`,
  `remove_unsubscribe`. Cada uma grava em `audit_logs` (ferramenta, ação, motivo, parâmetros), visível
  em "Auditoria".
- **Segredo não passa pelo MCP**: gerar token `cl_`, cadastrar chave de provider e segredo de webhook
  ficam só no painel, porque o que passa pelo MCP fica no histórico da conversa.

