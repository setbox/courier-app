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
     |> assign(:view, :html)
     |> assign(:width, :desktop)
     |> assign(:body, if(connected?(socket), do: load_body(email)))}
  end

  defp load_body(email) do
    case Emails.fetch_body(email) do
      {:ok, body} -> body
      {:error, _} -> :unavailable
    end
  end

  @impl true
  def handle_event("view", %{"view" => view}, socket) when view in ["html", "text"],
    do: {:noreply, assign(socket, :view, String.to_existing_atom(view))}

  def handle_event("width", %{"width" => width}, socket) when width in ["desktop", "mobile"],
    do: {:noreply, assign(socket, :width, String.to_existing_atom(width))}

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

      <div
        :if={Emails.sandbox?(@email)}
        id="sandbox-notice"
        class="rounded-box border border-warning/30 bg-warning/10 p-4 text-sm"
      >
        Sandbox: o Courier guardou este e-mail e não enviou a ninguém.
      </div>

      <div class="grid items-start gap-4 lg:grid-cols-2">
        <div class="flex min-w-0 flex-col gap-4">
          <.card_section title="Envio">
            <dl class="grid gap-x-4 gap-y-2 text-sm sm:grid-cols-[150px_minmax(0,1fr)]">
              <dt class="font-semibold text-neutral">Id</dt>
              <dd class="break-all"><code class="text-xs">{@email.id}</code></dd>
              <dt class="font-semibold text-neutral">Remetente</dt>
              <dd>{@email.from}</dd>
              <%= if @email.reply_to do %>
                <dt class="font-semibold text-neutral">Responder para</dt>
                <dd>{@email.reply_to}</dd>
              <% end %>
              <dt class="font-semibold text-neutral">Categoria</dt>
              <dd>{Format.category(@email.category)}</dd>
              <%= if @email.provider do %>
                <dt class="font-semibold text-neutral">Provider</dt>
                <dd>{Courier.Core.Apps.ChannelConfig.provider_label(@email.provider)}</dd>
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
                <dt class="font-semibold text-neutral">MessageID do provider</dt>
                <dd class="break-all"><code class="text-xs">{@email.provider_message_id}</code></dd>
              <% end %>
              <%= if @email.idempotency_key do %>
                <dt class="font-semibold text-neutral">Idempotency-Key</dt>
                <dd class="break-all"><code class="text-xs">{@email.idempotency_key}</code></dd>
              <% end %>
              <%= if @email.tag do %>
                <dt class="font-semibold text-neutral">Tag</dt>
                <dd>{@email.tag}</dd>
              <% end %>
              <%= if @email.metadata != %{} do %>
                <dt class="font-semibold text-neutral">Metadata</dt>
                <dd><code class="break-all text-xs">{Jason.encode!(@email.metadata)}</code></dd>
              <% end %>
            </dl>
          </.card_section>

          <.card id="recipients">
            <h2 class="px-4 pt-4 pb-2 text-base font-semibold">Destinatários</h2>
            <div
              :for={r <- @email.recipients}
              class="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-base-300 px-4 py-2.5"
            >
              <span class="flex min-w-0 flex-1 flex-col">
                <span class="truncate text-sm font-semibold">{r.address}</span>
                <span class="text-xs text-neutral">
                  {r.kind} · abertura {Format.datetime(r.opened_at)} · clique {Format.datetime(
                    r.clicked_at
                  )}
                </span>
                <span :if={r.detail} class="text-xs text-neutral">{r.detail}</span>
              </span>
              <.pill tone={Format.tone(r.status)}>{Format.recipient_status(r.status)}</.pill>
            </div>
          </.card>

          <.card_section title="Eventos">
            <ol id="events" class="space-y-2">
              <li :for={ev <- @email.events} class="flex flex-wrap items-baseline gap-x-3 text-sm">
                <span class="tabular w-36 text-xs text-neutral">
                  {Format.datetime(ev.occurred_at)}
                </span>
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
                <:action :let={d}>
                  <.button phx-click="redeliver" phx-value-id={d.id}>Reenviar</.button>
                </:action>
              </.table>
            </div>
          </.card_section>
        </div>

        <.card class="flex min-w-0 flex-col lg:sticky lg:top-16" id="email-content">
          <div class="flex flex-wrap items-center justify-between gap-2 border-b border-base-300 px-4 py-2">
            <div role="tablist" aria-label="Formato do conteúdo" class="tabs tabs-border">
              <button
                :for={{view, label} <- [html: "HTML", text: "Texto"]}
                type="button"
                role="tab"
                aria-selected={to_string(@view == view)}
                phx-click="view"
                phx-value-view={view}
                class={["tab", @view == view && "tab-active"]}
              >
                {label}
              </button>
            </div>
            <div
              :if={@view == :html}
              role="group"
              aria-label="Largura da prévia"
              class="flex gap-0.5 rounded-field border border-base-300 p-0.5"
            >
              <button
                :for={{width, label} <- [desktop: "Computador", mobile: "Celular"]}
                type="button"
                aria-pressed={to_string(@width == width)}
                phx-click="width"
                phx-value-width={width}
                class={[
                  "h-7 cursor-pointer rounded-selector px-2.5 text-xs font-semibold",
                  if(@width == width,
                    do: "bg-primary text-primary-content",
                    else: "text-neutral hover:bg-base-200"
                  )
                ]}
              >
                {label}
              </button>
            </div>
          </div>
          <dl class="grid grid-cols-[64px_minmax(0,1fr)] gap-x-2 gap-y-0.5 border-b border-base-300 px-4 py-2 text-xs">
            <dt class="text-neutral">De</dt>
            <dd class="truncate">{@email.from}</dd>
            <dt class="text-neutral">Para</dt>
            <dd class="truncate">{Enum.map_join(@email.recipients, ", ", & &1.address)}</dd>
            <dt class="text-neutral">Assunto</dt>
            <dd class="truncate font-semibold">{@email.subject}</dd>
          </dl>
          <div class="h-[680px] overflow-auto bg-base-200 p-4" id="email-body">
            <p :if={is_nil(@body)} class="text-sm text-neutral">Carregando o conteúdo...</p>
            <p :if={@body == :unavailable} class="text-sm text-error">
              O conteúdo não está disponível no armazenamento.
            </p>
            <%= if is_map(@body) do %>
              <iframe
                :if={@view == :html and @body.html_body}
                sandbox=""
                srcdoc={@body.html_body}
                class={[
                  "mx-auto block h-full rounded-box bg-white",
                  if(@width == :mobile, do: "w-[375px]", else: "w-full max-w-[680px]")
                ]}
              >
              </iframe>
              <p :if={@view == :html and is_nil(@body.html_body)} class="text-sm text-neutral">
                Este e-mail não tem versão em HTML.
              </p>
              <pre
                :if={@view == :text and @body.text_body}
                class="rounded-box bg-base-100 p-4 text-sm whitespace-pre-wrap"
              >{@body.text_body}</pre>
              <p :if={@view == :text and is_nil(@body.text_body)} class="text-sm text-neutral">
                Este e-mail não tem versão em texto.
              </p>
            <% end %>
          </div>
        </.card>
      </div>
    </Layouts.app>
    """
  end
end
