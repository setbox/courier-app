# CLAUDE.md

## Como rodar

`make dev` sobe o app com IEx na **porta 4012** (porta fixa por plataforma Setbox). `make setup`
instala dependências, cria o banco, migra e roda o seed. `make` sozinho lista os alvos.

Seed: cria o administrador `jackson@setbox.com.br` (ou `ADMIN_EMAIL`), já confirmado. Senha de
`ADMIN_PASSWORD`; em dev, sem ela, `root@Setbox`; fora de dev, gerada e impressa (variável vazia vale
como ausente). Conta que já tem senha não é tocada. Na release: `bin/seed` (`Courier.Release.seed/0`).

E-mail: Postmark em produção (`POSTMARK_SERVER_API_TOKEN`, obrigatório: sem ele a release não sobe),
remetente de `MAIL_FROM_NAME`/`MAIL_FROM` (padrão `Courier <courier@setbox.com.br>`). Em dev,
`Swoosh.Adapters.Local` e `/dev/mailbox`.

Antes de fechar qualquer tarefa: `mix precommit`.

## Documentação

**A documentação do produto vive em `docs/`** (decisões, domínio, API, operação). Leia antes de
implementar. A base do Obsidian (`~/obsidian/setbox/produtos/courier/`) descreve um desenho anterior
(templates, regras, envelope) e **não vale** até ser realinhada: não implemente nada a partir dela.

## O que o Courier faz

Recebe pedidos de envio por API REST (`/api/v1`, header `Api-Key` com o token `cl_` do ambiente),
responde `202`, guarda (metadados no Postgres, corpo no MinIO) e enfileira no Oban, que entrega pelo
provider do ambiente. Hoje só e-mail pelo Postmark. Eventos do Postmark chegam por webhook e são
repassados à aplicação cliente por webhook assinado (HMAC). Retenção de 90 dias.

Vocabulário: **aplicação** (`App`, tabela `apps`; não `Application`, que é a aplicação OTP),
**ambiente**, **configuração de canal**, **e-mail**, **destinatário**, **evento**, **entrega de
webhook**. Ferramenta interna da Setbox: não há organização nem tenant.

## Stack

Mesmas versões do `../../pjpark/pjpark-app`: Erlang 27.3.1, Elixir 1.18.3-otp-27, Phoenix 1.8,
LiveView 1.1, Ecto/Postgres com `binary_id`, Oban (painel em `/oban`, só autenticado), Req,
Swoosh, Tailwind v4 + daisyUI, **sem gettext**: mensagens em português escritas direto no código.

Contextos em `lib/courier/core/` (`Accounts`, `Apps`, `Emails`, `Webhooks`, `Storage`), conectores
em `lib/courier/connectors/` (`Google`, `Postmark`), workers em `lib/courier/workers/`, API em
`lib/courier_web/controllers/api/`. Segredos cifrados com `cloak_ecto` (`Courier.Vault`, chave em
`CLOAK_KEY`). Nos testes, Postmark, MinIO e o HTTP do webhook de saída são trocados por dublês em
`test/support/stubs/`.

## Autenticação

`phx.gen.auth` adaptado ao desenho do PJ Park:

- **Sem cadastro público**: só o administrador cria ou convida usuários (não há `/register`).
- **E-mail e senha** (8 a 72 caracteres). Sem confirmar o e-mail, não entra. Confirmação vale 7
  dias; redefinição, 1 dia; sessão, 14 dias.
- E-mail inexistente e senha errada respondem igual.
- **Conta Google** (`Courier.Connectors.Google`, sobre o `Req`), em `/auth/google`. `state` na
  sessão, comparado com `Plug.Crypto.secure_compare/2`. Só e-mail verificado entra, e só de conta que
  já existe: o Google não cria conta. Conta não confirmada passa a confirmada e perde a senha e os
  tokens ao entrar pelo Google. Sem
  `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET`, o botão some. Callback em dev:
  `http://localhost:4012/auth/google/callback`.
- Telas públicas (`/login`, `/reset-password`, `/confirm`) usam
  `CourierWeb.AuthLayout`: formulário em 30% à esquerda, mascote em 70% à direita (`webp` com `jpg`
  de reserva; abaixo de `lg` o painel não é renderizado). O `flash_group` fica fora da grade.

## Visual

Guia de estilos da Setbox, o mesmo do Vitrine (`../../../labs/vitrine/vitrine-app`): Manrope, vermelho
`#AF0914` em botão e texto no claro, cubo da Setbox no cabeçalho, barra superior com menu lateral
(`Layouts.app`, atributo `active`), conteúdo em cartões (`CourierWeb.PanelComponents`: `card`,
`card_section`, `empty_state`, `pill`), avisos em toast no canto inferior. O tema escuro usa os
tokens escuros do guia de marca (`~/obsidian/setbox/marca/identidade-visual.md`): botão `#E10C19`,
texto vermelho `#FB0D1C`. Use cores por token (`base-*`, `primary`, `neutral`), nunca hex fixo,
para os dois temas funcionarem.

**Formulário nunca divide a tela com listagem ou detalhe.** Criar, editar e configurar abrem
sempre uma tela própria (`/new`, `/:id/edit`, `/:id/<assunto>`), com um `<.card>` contendo os campos
empilhados e, no rodapé à direita, "Cancelar" (volta) e "Salvar" (`variant="primary"`); salvar volta
para o detalhe com aviso. Listagem e detalhe só mostram dados e ações de um clique (botão que navega
para o formulário, regenerar token, reenviar webhook). Exceção: os filtros de busca de uma listagem.
Referência: `AppLive.Form`, `EnvironmentLive.Form`, `EnvironmentLive.EmailConfig`.

**Lista clicável dentro de cartão** (`<.card>` com `<.link>` por linha e `hover:bg-base-200`): o
`card` já recorta o conteúdo (`overflow-hidden`) para o hover não apagar os cantos arredondados.
Não tire isso; por consequência, menu suspenso (dropdown) não vai dentro de `<.card>`.

**Botão ao lado de campo**, se um dia for inevitável: mesma altura do `<.input>` (40px, ou seja, sem
`btn-sm`) e alinhado ao campo, não ao fundo da linha, para não desalinhar quando o campo mostra erro.
Confira com screenshot.

