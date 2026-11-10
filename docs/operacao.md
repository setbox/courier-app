# Operação

## Variáveis de ambiente (produção)

| Variável | Obrigatória | Uso |
|---|---|---|
| `DATABASE_URL` | sim | Postgres |
| `SECRET_KEY_BASE` | sim | Phoenix |
| `PHX_HOST` | sim | Monta a URL do webhook do Postmark (`https://<host>/webhooks/postmark/<ambiente>`) |
| `CLOAK_KEY` | sim | Chave AES-256 (base64, 32 bytes) que cifra Server Tokens e segredos. **Perder a chave torna as credenciais ilegíveis**: guarde fora da VPS (issue #1). Gere com `openssl rand -base64 32` |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | sim | Credencial do MinIO |
| `S3_HOST` | sim | Host do MinIO na rede interna |
| `S3_PORT`, `S3_SCHEME`, `S3_BUCKET` | não | Padrões `9000`, `http://`, `courier` |
| `POSTMARK_SERVER_API_TOKEN` | sim | E-mails do próprio Courier (confirmação, senha). Não é usado no envio das aplicações, que usa o token de cada ambiente |
| `MAIL_FROM`, `MAIL_FROM_NAME` | não | Remetente desses e-mails |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | não | Entrada pelo Google |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | não | Seed do administrador |

Sem `CLOAK_KEY`, `S3_HOST` ou as credenciais do MinIO, a release não sobe.

## MinIO

Bucket `courier`, privado. O corpo de cada e-mail fica em
`<app_id>/<environment_id>/<AAAA>/<MM>/<email_id>.json`. O seed (`bin/seed`) cria o bucket se não
existir.

Em dev, o MinIO compartilhado de `~/workspace/setbox/infra/local/docker/minio/latest` (porta 9000), com
a credencial no `.envrc` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).

## Postmark

Cada ambiente usa o Server Token do seu próprio server no Postmark. Ao salvar a configuração, o Courier
cadastra (ou atualiza) o webhook do server com todos os eventos, apontando para
`/webhooks/postmark/<environment_id>` com Basic Auth `courier:<senha do ambiente>`. Se o cadastro
falhar, o erro aparece na tela e a configuração continua salva; dá para cadastrar de novo ou à mão.

Em dev o Postmark não alcança `localhost`, então os eventos de entrega não chegam; o envio funciona.

## Filas (Oban)

| Fila | Concorrência | Worker |
|---|---|---|
| `emails` | 20 | `Courier.Workers.SendEmail` |
| `webhooks` | 10 | `Courier.Workers.DeliverWebhook` |
| `maintenance` | 1 | `Courier.Workers.PurgeExpired` (cron `0 6 * * *`, UTC) |

Painel em `/oban`, só com login.

## Retenção

90 dias para tudo: o job diário apaga os e-mails mais antigos (com destinatários, eventos e entregas)
e o corpo no MinIO, em lotes de 500.
