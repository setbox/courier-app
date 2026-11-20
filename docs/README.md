# Courier - documentação

O Courier recebe pedidos de envio de mensagem por API REST, guarda, enfileira e entrega pelo
provider configurado. Nesta fase o único canal é e-mail, pelo Postmark, pelo Brevo ou pelo Sandbox do Courier (só testes: guarda e não envia).

Esta pasta é a fonte de verdade do produto por enquanto. A base de conhecimento do Obsidian
(`~/obsidian/setbox/produtos/courier/`) descreve um desenho anterior (templates, regras, envelope) e
**não vale** até ser realinhada.

| Documento | Conteúdo |
|---|---|
| [decisoes.md](decisoes.md) | O que foi decidido, com data e motivo |
| [dominio.md](dominio.md) | Entidades, estados e o fluxo de um e-mail |
| [api.md](api.md) | Contrato da API REST e do webhook enviado ao cliente |
| [operacao.md](operacao.md) | Variáveis de ambiente, MinIO, Postmark, Brevo, sandbox, filas e retenção |
