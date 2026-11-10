# CLAUDE.md

## Como rodar

`make dev` sobe o app com IEx na **porta 4012** (porta fixa por plataforma Setbox). `make setup`
instala dependências, cria o banco, migra e roda o seed. `make` sozinho lista os alvos.

Seed: cria o administrador `jackson@setbox.com.br` (ou `ADMIN_EMAIL`), já confirmado. Senha de
`ADMIN_PASSWORD`; em dev, sem ela, `root@Setbox`; fora de dev, gerada e impressa. Conta que já tem
senha não é tocada.

Antes de fechar qualquer tarefa: `mix precommit`.

## Documentação

Base de conhecimento: `~/obsidian/setbox/produtos/courier/` (MOC em `Courier.md`).

## Stack

Mesmas versões do `../../pjpark/pjpark-app`: Erlang 27.3.1, Elixir 1.18.3-otp-27, Phoenix 1.8,
LiveView 1.1, Ecto/Postgres com `binary_id`, Oban (painel em `/oban`, só autenticado), Req,
Swoosh, Tailwind v4 + daisyUI com temas `light` e `dark` (paleta herdada do PJ Park), **sem
gettext**: mensagens em português escritas direto no código.

Contextos em `lib/courier/core/`, conectores em `lib/courier/connectors/`.

## Autenticação

`phx.gen.auth` adaptado ao desenho do PJ Park:

- **E-mail e senha** (8 a 72 caracteres). Sem confirmar o e-mail, não entra. Confirmação vale 7
  dias; redefinição, 1 dia; sessão, 14 dias.
- E-mail inexistente e senha errada respondem igual.
- **Conta Google** (`Courier.Connectors.Google`, sobre o `Req`), em `/auth/google`. `state` na
  sessão, comparado com `Plug.Crypto.secure_compare/2`. Só e-mail verificado entra. Conta nova nasce
  confirmada e sem senha; conta não confirmada perde a senha e os tokens ao entrar pelo Google. Sem
  `GOOGLE_CLIENT_ID` e `GOOGLE_CLIENT_SECRET`, o botão some. Callback em dev:
  `http://localhost:4012/auth/google/callback`.
- Telas públicas (`/login`, `/register`, `/reset-password`, `/confirm`) usam
  `CourierWeb.AuthLayout`: formulário em 30% à esquerda, mascote em 70% à direita (`webp` com `jpg`
  de reserva; abaixo de `lg` o painel não é renderizado). O `flash_group` fica fora da grade.
