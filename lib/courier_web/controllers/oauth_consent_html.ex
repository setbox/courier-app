defmodule CourierWeb.OAuthConsentHTML do
  use CourierWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.card class="mx-auto w-full max-w-md space-y-4 p-6">
        <div class="space-y-1">
          <h1 class="text-xl font-semibold">Conectar {@request.client.name}?</h1>
          <p class="text-sm text-neutral">
            O assistente de IA vai consultar e operar o Courier em seu nome, pelo MCP.
          </p>
        </div>

        <dl
          id="oauth-consent-details"
          class="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-[140px_minmax(0,1fr)]"
        >
          <dt class="font-semibold text-neutral">Conta</dt>
          <dd>{@current_scope.user.email}</dd>
          <dt class="font-semibold text-neutral">A resposta volta para</dt>
          <dd class="break-all">{@return_host}</dd>
        </dl>

        <div class="space-y-2 text-sm">
          <p>Ele vai poder:</p>
          <ul class="list-disc space-y-1 pl-5 text-neutral">
            <li>ler o Painel, as falhas, os e-mails, as aplicações, os ambientes e a auditoria;</li>
            <li>
              mandar e-mail de teste, reenviar webhook, criar aplicação e ambiente, mudar listas de
              destinatários e reinscrever no marketing, com sua confirmação e motivo em cada ação.
            </li>
          </ul>
          <p class="text-neutral">Não vê nem troca token, chave de provider ou segredo de webhook.</p>
        </div>

        <form id="oauth-consent-form" action={~p"/oauth/authorize"} method="post">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <input :for={{name, value} <- @hidden} type="hidden" name={name} value={value} />
          <div class="flex justify-end gap-2">
            <button id="oauth-deny" name="decision" value="deny" class="btn">Recusar</button>
            <button id="oauth-allow" name="decision" value="allow" class="btn btn-primary">
              Permitir
            </button>
          </div>
        </form>

        <p class="text-xs text-neutral">Você revoga o acesso quando quiser, em Acesso pelo MCP.</p>
      </.card>
    </Layouts.app>
    """
  end

  def invalid(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.card id="oauth-invalid" class="mx-auto w-full max-w-md space-y-2 p-6">
        <h1 class="text-xl font-semibold">Pedido de conexão inválido</h1>
        <p class="text-sm text-neutral">Comece a conexão de novo pelo assistente de IA.</p>
      </.card>
    </Layouts.app>
    """
  end
end
