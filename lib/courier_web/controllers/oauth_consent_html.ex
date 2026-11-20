defmodule CourierWeb.OAuthConsentHTML do
  use CourierWeb, :html

  attr :flash, :map, required: true
  slot :inner_block, required: true

  defp consent_page(assigns) do
    ~H"""
    <main class="flex min-h-screen flex-col items-center justify-center gap-6 bg-base-200 px-4 py-10">
      <div class="flex items-center gap-2.5">
        <img src={~p"/images/logo.svg"} alt="" class="h-7 w-auto" />
        <span class="text-xl font-bold">Courier</span>
      </div>
      <section class="w-full max-w-md space-y-4 rounded-box border border-base-300 bg-base-100 p-6">
        {render_slot(@inner_block)}
      </section>
    </main>
    <CourierWeb.Layouts.flash_group flash={@flash} />
    """
  end

  def show(assigns) do
    ~H"""
    <.consent_page flash={@flash}>
      <div class="space-y-1">
        <h1 class="text-xl font-semibold">Conectar {@request.client.name}?</h1>
        <p class="text-sm text-neutral">
          O assistente de IA vai consultar e operar o Courier em seu nome, pelo MCP.
        </p>
      </div>

      <dl id="oauth-consent-details" class="space-y-2 text-sm">
        <div>
          <dt class="text-xs text-neutral">Conta</dt>
          <dd>{@current_scope.user.email}</dd>
        </div>
        <div>
          <dt class="text-xs text-neutral">A resposta volta para</dt>
          <dd class="break-all">{@return_host}</dd>
        </div>
      </dl>

      <div class="space-y-2 text-sm">
        <p>Ele vai poder:</p>
        <ul class="list-disc space-y-1 pl-5 text-neutral">
          <li>ler o Painel, as falhas, os e-mails, as aplicações, os ambientes e a auditoria;</li>
          <li>
            criar aplicação e ambiente, configurar o Sandbox do Courier, gerar token de envio, mandar
            e-mail de teste, reenviar webhook, mudar listas de destinatários e reinscrever no marketing,
            com sua confirmação e motivo em cada ação.
          </li>
        </ul>
        <p class="text-neutral">Não vê nem troca chave de provider ou segredo de webhook.</p>
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
    </.consent_page>
    """
  end

  def invalid(assigns) do
    ~H"""
    <.consent_page flash={@flash}>
      <h1 id="oauth-invalid" class="text-xl font-semibold">Pedido de conexão inválido</h1>
      <p class="text-sm text-neutral">Comece a conexão de novo pelo assistente de IA.</p>
    </.consent_page>
    """
  end
end
