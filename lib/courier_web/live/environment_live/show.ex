defmodule CourierWeb.EnvironmentLive.Show do
  use CourierWeb, :live_view

  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig
  alias CourierWeb.Format

  @impl true
  def mount(%{"app_id" => app_id, "id" => id}, _session, socket) do
    environment = Apps.get_environment!(app_id, id)

    {:ok,
     socket
     |> assign(:page_title, "#{environment.app.name} · #{environment.name}")
     |> assign(:environment, environment)
     |> assign(:config, Apps.email_config(environment))
     |> assign(:revealed_token, nil)
     |> assign(:revealed_secret, nil)}
  end

  @impl true
  def handle_event("regenerate_token", _params, socket) do
    {:ok, environment, token} = Apps.regenerate_client_token(socket.assigns.environment)

    {:noreply,
     socket
     |> assign(:environment, %{environment | app: socket.assigns.environment.app})
     |> assign(:revealed_token, token)}
  end

  def handle_event("register_inbound", _params, socket) do
    config = Apps.register_postmark_webhook(socket.assigns.config, inbound_url(socket))
    {:noreply, socket |> assign(:config, config) |> put_inbound_flash(config)}
  end

  def handle_event("regenerate_inbound", _params, socket) do
    config = Apps.regenerate_inbound_password(socket.assigns.config, inbound_url(socket))
    {:noreply, socket |> assign(:config, config) |> put_inbound_flash(config)}
  end

  def handle_event("regenerate_secret", _params, socket) do
    {:ok, environment, secret} = Apps.regenerate_webhook_secret(socket.assigns.environment)

    {:noreply,
     socket
     |> assign(:environment, %{environment | app: socket.assigns.environment.app})
     |> assign(:revealed_secret, secret)}
  end

  defp put_inbound_flash(socket, %ChannelConfig{postmark_webhook_error: nil}),
    do: put_flash(socket, :info, "Webhook cadastrado no Postmark.")

  defp put_inbound_flash(socket, %ChannelConfig{}),
    do: put_flash(socket, :warning, "O webhook não foi cadastrado no Postmark.")

  defp inbound_url(socket), do: url(~p"/webhooks/postmark/#{socket.assigns.environment}")

  defp list_summary([]), do: "Vazia"
  defp list_summary(entries), do: Enum.join(entries, ", ")

  defp yes_no(true), do: "Sim"
  defp yes_no(false), do: "Não"

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:inbound_url, url(~p"/webhooks/postmark/#{assigns.environment}"))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:apps}>
      <.back_link navigate={~p"/apps/#{@environment.app}"}>{@environment.app.name}</.back_link>

      <.header>
        {@environment.name}
        <:subtitle>
          Ambiente <code>{@environment.slug}</code> de {@environment.app.name}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/apps/#{@environment.app}/environments/#{@environment}/edit"}>
            Editar
          </.button>
          <.button navigate={~p"/emails?#{[environment_id: @environment.id]}"}>Ver e-mails</.button>
        </:actions>
      </.header>

      <.card_section title="Token de envio">
        <:subtitle>
          Vai no header <code>Api-Key</code>. Regenerar invalida o token anterior na hora.
        </:subtitle>

        <div
          :if={@revealed_token}
          id="revealed-token"
          class="space-y-1 rounded-box border border-warning/40 bg-warning/10 p-4"
        >
          <p class="text-sm font-semibold">Copie agora: este token não será mostrado de novo.</p>
          <code class="block text-sm break-all">{@revealed_token}</code>
        </div>

        <div class="flex flex-wrap items-center gap-4">
          <span :if={@environment.client_token_hint} class="text-sm">
            <.pill tone={:ok}>cl_…{@environment.client_token_hint}</.pill>
            <span class="ml-2 text-neutral">
              gerado em {Format.datetime(@environment.client_token_generated_at)}
            </span>
          </span>
          <.pill :if={is_nil(@environment.client_token_hint)} tone={:pending}>
            Nenhum token gerado
          </.pill>
          <.button
            id="regenerate-token"
            phx-click="regenerate_token"
            data-confirm={
              @environment.client_token_hint && "O token atual deixa de funcionar agora. Continuar?"
            }
          >
            {if @environment.client_token_hint, do: "Regenerar token", else: "Gerar token"}
          </.button>
        </div>
      </.card_section>

      <.card_section title="E-mail · Postmark">
        <:subtitle>Credencial do server do Postmark, remetente padrão e rastreio.</:subtitle>

        <div :if={is_nil(@config)}>
          <.pill tone={:pending}>Não configurado</.pill>
        </div>

        <dl
          :if={@config}
          id="email-config"
          class="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-[180px_minmax(0,1fr)]"
        >
          <dt class="font-semibold text-neutral">Server API Token</dt>
          <dd><code>••••{@config.server_token_hint}</code></dd>
          <dt class="font-semibold text-neutral">Remetente</dt>
          <dd>{@config.from_name} &lt;{@config.from_email}&gt;</dd>
          <dt class="font-semibold text-neutral">Message stream</dt>
          <dd><code>{@config.message_stream}</code></dd>
          <dt class="font-semibold text-neutral">Rastrear aberturas</dt>
          <dd>{yes_no(@config.track_opens)}</dd>
          <dt class="font-semibold text-neutral">Rastrear cliques</dt>
          <dd>{yes_no(@config.track_links)}</dd>
        </dl>

        <div>
          <.button
            variant="primary"
            navigate={~p"/apps/#{@environment.app}/environments/#{@environment}/email"}
          >
            {if @config, do: "Editar configuração", else: "Configurar e-mail"}
          </.button>
        </div>
      </.card_section>

      <.card_section :if={@config} title="Webhook do Postmark">
        <:subtitle>
          O Courier cadastra este webhook no Postmark ao salvar a configuração. Para cadastrar à mão,
          use a URL e a credencial abaixo (Basic Auth), com todos os eventos marcados.
        </:subtitle>

        <div
          :if={@config.postmark_webhook_error}
          id="inbound-error"
          class="rounded-box border border-error/30 bg-error/10 p-4 text-sm text-error"
        >
          {@config.postmark_webhook_error}
        </div>
        <div :if={is_nil(@config.postmark_webhook_error) && @config.postmark_webhook_id}>
          <.pill tone={:ok}>Cadastrado no Postmark (webhook {@config.postmark_webhook_id})</.pill>
        </div>

        <dl class="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-[180px_minmax(0,1fr)]">
          <dt class="font-semibold text-neutral">URL</dt>
          <dd><code class="break-all">{@inbound_url}</code></dd>
          <dt class="font-semibold text-neutral">Usuário</dt>
          <dd><code>{Apps.inbound_username()}</code></dd>
          <dt class="font-semibold text-neutral">Senha</dt>
          <dd><code class="break-all">{@config.inbound_password}</code></dd>
        </dl>

        <div class="flex flex-wrap gap-2">
          <.button phx-click="register_inbound">Cadastrar de novo no Postmark</.button>
          <.button
            phx-click="regenerate_inbound"
            data-confirm="A senha atual deixa de valer. O Courier recadastra o webhook no Postmark. Continuar?"
          >
            Gerar nova senha
          </.button>
        </div>
      </.card_section>

      <.card_section title="Destinatários permitidos e bloqueados">
        <:subtitle>
          Com a lista de permitidos preenchida, só ela recebe. Os bloqueados nunca recebem.
        </:subtitle>

        <dl
          id="recipient-lists"
          class="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-[180px_minmax(0,1fr)]"
        >
          <dt class="font-semibold text-neutral">Permitidos</dt>
          <dd>{list_summary(@environment.allowed_recipients)}</dd>
          <dt class="font-semibold text-neutral">Bloqueados</dt>
          <dd>{list_summary(@environment.blocked_recipients)}</dd>
        </dl>

        <div>
          <.button navigate={~p"/apps/#{@environment.app}/environments/#{@environment}/recipients"}>
            Editar listas
          </.button>
        </div>
      </.card_section>

      <.card_section title="Webhook para a aplicação">
        <:subtitle>
          O Courier avisa cada evento por POST na URL, assinado no header <code>Courier-Signature</code>.
        </:subtitle>

        <div
          :if={@revealed_secret}
          id="revealed-secret"
          class="space-y-1 rounded-box border border-warning/40 bg-warning/10 p-4"
        >
          <p class="text-sm font-semibold">
            Segredo de assinatura. Copie agora: ele não será mostrado de novo.
          </p>
          <code class="block text-sm break-all">{@revealed_secret}</code>
        </div>

        <dl class="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-[180px_minmax(0,1fr)]">
          <dt class="font-semibold text-neutral">URL</dt>
          <dd>
            <code :if={@environment.webhook_url} class="break-all">{@environment.webhook_url}</code>
            <span :if={is_nil(@environment.webhook_url)} class="text-neutral">Não configurado</span>
          </dd>
        </dl>

        <div class="flex flex-wrap gap-2">
          <.button navigate={~p"/apps/#{@environment.app}/environments/#{@environment}/webhook"}>
            {if @environment.webhook_url, do: "Editar URL", else: "Configurar webhook"}
          </.button>
          <.button
            :if={@environment.webhook_secret}
            phx-click="regenerate_secret"
            data-confirm="O segredo atual deixa de valer agora. Continuar?"
          >
            Gerar novo segredo
          </.button>
        </div>
      </.card_section>
    </Layouts.app>
    """
  end
end
