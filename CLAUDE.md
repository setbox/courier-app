# CLAUDE.md

## Como rodar

`make dev` sobe o app com IEx na **porta 4012** (porta fixa por plataforma Setbox). `make setup`
instala dependências, cria o banco, migra e roda o seed. `make` sozinho lista os alvos.

Seed: cria o administrador `jackson@setbox.com.br` (ou `ADMIN_EMAIL`; vazia vale como ausente), já
confirmado e sem senha: entra pelo Google. Conta que já existe não é tocada. Na release: `bin/seed`
(`Courier.Release.seed/0`).

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
provider do ambiente. Hoje só e-mail, pelo Postmark, pelo Brevo ou pelo Sandbox do Courier (ambientes de
teste: o Courier guarda o e-mail, mostra em E-mails e não envia). Eventos do Postmark e do Brevo chegam por webhook e são
repassados à aplicação cliente por webhook assinado (HMAC). Retenção de 90 dias.

Vocabulário: **aplicação** (`App`, tabela `apps`; não `Application`, que é a aplicação OTP),
**ambiente**, **configuração de canal**, **e-mail**, **destinatário**, **evento**, **entrega de
webhook**. Ferramenta interna da Setbox: não há organização nem tenant.

## Stack

Mesmas versões do `../../pjpark/pjpark-app`: Erlang 27.3.1, Elixir 1.18.3-otp-27, Phoenix 1.8,
LiveView 1.1, Ecto/Postgres com `binary_id`, Oban (painel em `/oban`, só autenticado), Req,
Swoosh, Tailwind v4 + daisyUI, **sem gettext**: mensagens em português escritas direto no código.

Contextos em `lib/courier/core/` (`Accounts`, `Apps`, `Emails`, `Webhooks`, `Storage`), conectores
em `lib/courier/connectors/` (`Google`, `Postmark`, `Brevo`), workers em `lib/courier/workers/`, API em
`lib/courier_web/controllers/api/`. Segredos cifrados com `cloak_ecto` (`Courier.Vault`, chave em
`CLOAK_KEY`). Nos testes, Postmark, Brevo, MinIO e o HTTP do webhook de saída são trocados por dublês em
`test/support/stubs/`.

## Autenticação

**Só conta Google** (decidido em 2026-11-20): não há senha, cadastro, redefinição, confirmação por
e-mail nem tela de conta.

- **Conta Google** (`Courier.Connectors.Google`, sobre o `Req`), em `/auth/google`. `state` na
  sessão, comparado com `Plug.Crypto.secure_compare/2`. Só e-mail verificado entra, e só de conta que
  já existe: o Google não cria conta (o administrador do seed é a primeira). Conta não confirmada
  passa a confirmada ao entrar.
- Sessão de 14 dias, em cookie assinado, gravada a cada entrada.
- `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET` também em dev (`.envrc`, o mesmo client da produção).
  Sem eles, `/login` mostra o aviso e ninguém entra. Callback em dev:
  `http://localhost:4012/auth/google/callback`, cadastrada no client do Google.
- A tela pública (`/login`) usa
  `CourierWeb.AuthLayout`: formulário em 30% à esquerda, mascote em 70% à direita (`webp` com `jpg`
  de reserva; abaixo de `lg` o painel não é renderizado). O `flash_group` fica fora da grade.

## Visual

Guia de estilos da Setbox em `../../../divisoes/setbox/setbox-stylebook`, na **densidade compacta** de app.
O tema daisyUI vem pronto do guia: `assets/css/setbox-daisyui.css` é cópia de `dist/setbox-daisyui.css`,
importada no `app.css`; não edite a cópia, copie de novo quando a primeira linha (versão e hash) mudar no
guia. Corpo de 14px, título de tela `text-xl font-semibold`, painel `p-4`, linha de lista `px-4 py-2.5`,
controle de 36px, raio 8/6/4px. Manrope. **Um vermelho só para interface:** `primary` (#AF0914 no claro,
#E10C19 no escuro) em botão, item ativo do rail, controle ligado (`checkbox-primary`), foco e borda do
campo em foco; não use `accent`. Tela de app em **largura total**, mesma margem dos dois lados, sem
largura máxima em cartão, lista, tabela ou formulário (campos em grade `sm:grid-cols-2 xl:grid-cols-3`).
Menu em rail à esquerda (Painel, Aplicações, E-mails, Falhas, Providers; cubo da Setbox no topo, ícone e
rótulo por item; abaixo de `md` vira menu na barra), barra superior com o seletor de tema (um ícone,
sol ou lua) e a conta (`Layouts.app`, atributo `active`), conteúdo em cartões (`CourierWeb.PanelComponents`:
`card`, `card_section`, `empty_state`, `pill`), gráficos de linha em `CourierWeb.ChartComponents`, avisos
em toast no canto inferior. Use cores por token (`base-*`, `primary`, `neutral`, `success`, `warning`,
`error`, `info`), nunca hex fixo, para os dois temas funcionarem.

**Formulário nunca divide a tela com listagem ou detalhe.** Criar, editar e configurar abrem
sempre uma tela própria (`/new`, `/:id/edit`, `/:id/<assunto>`), com um `<.card>` contendo os campos
empilhados e, no rodapé à direita, "Cancelar" (volta) e "Salvar" (`variant="primary"`); salvar volta
para o detalhe com aviso. Listagem e detalhe só mostram dados e ações de um clique (botão que navega
para o formulário, regenerar token, reenviar webhook). Exceção: os filtros de busca de uma listagem.
Referência: `AppLive.Form`, `EnvironmentLive.Form`, `EnvironmentLive.EmailConfig`.

**Lista clicável dentro de cartão** (`<.card>` com `<.link>` por linha e `hover:bg-base-200`): o
`card` já recorta o conteúdo (`overflow-hidden`) para o hover não apagar os cantos arredondados.
Não tire isso; por consequência, menu suspenso (dropdown) não vai dentro de `<.card>`.

**Botão ao lado de campo**, se um dia for inevitável: mesma altura do `<.input>` (36px no tema compacto,
ou seja, sem `btn-sm`) e alinhado ao campo, não ao fundo da linha, para não desalinhar quando o campo mostra erro.
Confira com screenshot.

