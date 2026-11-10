defmodule CourierWeb.EmailLive.Show do
  use CourierWeb, :live_view

  alias Courier.Core.{Emails, Webhooks}
  alias CourierWeb.Format

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    email = Emails.get_email!(id)

    {:ok,
     socket
     |> assign(:page_title, email.subject)
     |> assign(:email, email)
     |> assign(:deliveries, Webhooks.list_deliveries(email))
     |> assign(:body, nil)}
  end

  @impl true
  def handle_event("show_body", _params, socket) do
    body =
      case Emails.fetch_body(socket.assigns.email) do
        {:ok, body} -> body
        {:error, _} -> :unavailable
      end

    {:noreply, assign(socket, :body, body)}
  end

  def handle_event("redeliver", %{"id" => id}, socket) do
    {:ok, _} = id |> Webhooks.get_delivery!() |> Webhooks.redeliver()

    {:noreply,
     socket
     |> assign(:deliveries, Webhooks.list_deliveries(socket.assigns.email))
     |> put_flash(:info, "Reenvio agendado.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:emails}>
      <.link
        navigate={~p"/emails"}
        class="flex items-center gap-1 text-sm font-semibold text-neutral hover:text-primary"
      >
        <.icon name="hero-chevron-left-mini" class="size-4" /> E-mails
      </.link>

      <.header>
        {@email.subject}
        <:subtitle>
          {@email.environment.app.name} / {@email.environment.name}
        </:subtitle>
        <:actions>
          <.pill tone={Format.tone(@email.status)}>{Format.email_status(@email.status)}</.pill>
        </:actions>
      </.header>

      <.card_section title="Envio">
        <dl class="grid gap-x-6 gap-y-3 text-sm sm:grid-cols-[180px_minmax(0,1fr)]">
          <dt class="font-semibold text-neutral">Id</dt>
          <dd><code>{@email.id}</code></dd>
          <dt class="font-semibold text-neutral">Remetente</dt>
          <dd>{@email.from}</dd>
          <%= if @email.reply_to do %>
            <dt class="font-semibold text-neutral">Responder para</dt>
            <dd>{@email.reply_to}</dd>
          <% end %>
          <dt class="font-semibold text-neutral">Recebido</dt>
          <dd class="tabular">{Format.datetime(@email.inserted_at)}</dd>
          <dt class="font-semibold text-neutral">Enviado</dt>
          <dd class="tabular">{Format.datetime(@email.sent_at)}</dd>
          <%= if @email.failed_at do %>
            <dt class="font-semibold text-neutral">Falhou em</dt>
            <dd class="tabular">{Format.datetime(@email.failed_at)}</dd>
          <% end %>
          <%= if @email.error_message do %>
            <dt class="font-semibold text-neutral">Erro</dt>
            <dd class="text-error">
              {if @email.error_code, do: "#{@email.error_code}: "}{@email.error_message}
            </dd>
          <% end %>
          <dt class="font-semibold text-neutral">Tentativas</dt>
          <dd>{@email.attempts}</dd>
          <%= if @email.provider_message_id do %>
            <dt class="font-semibold text-neutral">MessageID (Postmark)</dt>
            <dd><code>{@email.provider_message_id}</code></dd>
          <% end %>
          <%= if @email.idempotency_key do %>
            <dt class="font-semibold text-neutral">Idempotency-Key</dt>
            <dd><code>{@email.idempotency_key}</code></dd>
          <% end %>
          <%= if @email.tag do %>
            <dt class="font-semibold text-neutral">Tag</dt>
            <dd>{@email.tag}</dd>
          <% end %>
          <%= if @email.metadata != %{} do %>
            <dt class="font-semibold text-neutral">Metadata</dt>
            <dd><code class="break-all">{Jason.encode!(@email.metadata)}</code></dd>
          <% end %>
        </dl>
      </.card_section>

      <.card_section title="Destinatários">
        <div class="overflow-x-auto">
          <.table id="recipients" rows={@email.recipients}>
            <:col :let={r} label="Endereço">{r.address}</:col>
            <:col :let={r} label="Tipo">{r.kind}</:col>
            <:col :let={r} label="Status">
              <.pill tone={Format.tone(r.status)}>{Format.recipient_status(r.status)}</.pill>
              <span :if={r.detail} class="mt-1 block text-xs text-neutral">{r.detail}</span>
            </:col>
            <:col :let={r} label="Abertura">{Format.datetime(r.opened_at)}</:col>
            <:col :let={r} label="Clique">{Format.datetime(r.clicked_at)}</:col>
          </.table>
        </div>
      </.card_section>

      <.card_section title="Eventos">
        <ol id="events" class="space-y-3">
          <li :for={ev <- @email.events} class="flex flex-wrap items-baseline gap-x-4 text-sm">
            <span class="tabular w-36 text-neutral">{Format.datetime(ev.occurred_at)}</span>
            <span class="font-semibold">{Format.event_type(ev.type)}</span>
            <span :if={ev.recipient} class="text-neutral">{ev.recipient.address}</span>
          </li>
        </ol>
      </.card_section>

      <.card_section title="Webhooks para a aplicação">
        <p :if={@deliveries == []} class="text-sm text-neutral">Nenhum webhook enviado.</p>
        <div :if={@deliveries != []} class="overflow-x-auto">
          <.table id="deliveries" rows={@deliveries}>
            <:col :let={d} label="Evento">{Format.event_type(d.email_event.type)}</:col>
            <:col :let={d} label="Status">
              <.pill tone={Format.tone(d.status)}>{Format.delivery_status(d.status)}</.pill>
            </:col>
            <:col :let={d} label="Tentativas">{d.attempts}</:col>
            <:col :let={d} label="Resposta">{d.response_status || d.response_error}</:col>
            <:col :let={d} label="Última tentativa">{Format.datetime(d.last_attempt_at)}</:col>
            <:action :let={d}>
              <.button phx-click="redeliver" phx-value-id={d.id}>Reenviar</.button>
            </:action>
          </.table>
        </div>
      </.card_section>

      <.card_section title="Conteúdo">
        <div :if={is_nil(@body)}>
          <.button phx-click="show_body" id="show-body">Mostrar conteúdo</.button>
        </div>
        <p :if={@body == :unavailable} class="text-sm text-error">
          O conteúdo não está disponível no armazenamento.
        </p>
        <div :if={is_map(@body)} class="space-y-3" id="email-body">
          <iframe
            :if={@body.html_body}
            sandbox=""
            srcdoc={@body.html_body}
            class="h-96 w-full rounded-box border border-base-300 bg-white"
          >
          </iframe>
          <pre
            :if={@body.text_body}
            class="rounded-box bg-base-200 p-4 text-sm whitespace-pre-wrap"
          >{@body.text_body}</pre>
        </div>
      </.card_section>
    </Layouts.app>
    """
  end
end
