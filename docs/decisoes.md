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
- **Credencial do provider cifrada com Cloak** (`Courier.Vault`, chave em `CLOAK_KEY`). A tela mostra
  só os últimos caracteres.
- **Remetente padrão na configuração**, com `from` opcional no pedido. Se o Postmark recusar
  (assinatura não verificada), o envio falha com o erro dele registrado.
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

## Só transacional (2026-11-10)

- **O Courier envia só e-mail transacional.** Não há link de descadastro nem gestão de inscrição: o
  stream configurado no ambiente deve ser um stream transacional do Postmark, que não insere rodapé
  de descadastro (só os streams de broadcast inserem). O evento `SubscriptionChange` continua
  registrado porque o Postmark pode suprimir um destinatário por bounce ou reclamação de spam.

## Consulta e retenção

- **Consultas**: por id, lista com filtros (status, destinatário, período, metadata,
  `Idempotency-Key`) e linha do tempo de eventos.
- **Retenção de 90 dias** para tudo. Metadados no Postgres; **corpo no MinIO**, gravado **antes** do
  202. MinIO fora do ar faz a API responder `503`, e o cliente retenta com a mesma `Idempotency-Key`.
