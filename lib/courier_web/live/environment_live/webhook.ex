defmodule CourierWeb.EnvironmentLive.Webhook do
  use CourierWeb, :live_view

  alias Courier.Core.Apps

  @impl true
  def mount(%{"app_id" => app_id, "id" => id}, _session, socket) do
    environment = Apps.get_environment!(app_id, id)

    {:ok,
     socket
     |> assign(:page_title, "Webhook · #{environment.name}")
     |> assign(:environment, environment)
     |> assign(:revealed_secret, nil)
     |> assign(:form, to_form(Apps.change_webhook(environment)))}
  end

  @impl true
  def handle_event("save", %{"environment" => params}, socket) do
    environment = socket.assigns.environment

    case Apps.update_webhook(environment, params) do
      {:ok, updated, nil} ->
        {kind, message} = saved_flash(updated)

        {:noreply,
         socket
         |> put_flash(kind, message)
         |> push_navigate(to: ~p"/apps/#{environment.app}/environments/#{environment}")}

      {:ok, updated, secret} ->
        {:noreply,
         socket
         |> assign(:environment, %{updated | app: environment.app})
         |> assign(:form, to_form(Apps.change_webhook(updated)))
         |> assign(:revealed_secret, secret)
         |> then(fn socket ->
           {kind, message} = saved_flash(updated)
           put_flash(socket, kind, message)
         end)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @event_hints %{
    sent: "O provider aceitou o e-mail",
    failed: "O provider recusou ou as tentativas acabaram",
    delivery: "Chegou à caixa do destinatário",
    not_found: "O endereço não existe (hard bounce)",
    bounce: "Outras devoluções: bloqueado, caixa cheia",
    spam_complaint: "O destinatário marcou como spam",
    open: "Abertura, quando o rastreio está ligado",
    click: "Clique em link, quando o rastreio está ligado",
    subscription_change: "Descadastro ou reinscrição"
  }

  defp saved_flash(%{webhook_url: url, webhook_events: []}) when is_binary(url),
    do: {:warning, "Webhook salvo sem nenhum evento marcado: nada será enviado à aplicação."}

  defp saved_flash(_environment), do: {:info, "Webhook salvo."}

  defp event_options do
    Enum.map(Courier.Core.Webhooks.event_types(), fn type ->
      {Atom.to_string(type), CourierWeb.Format.event_type(type), Map.fetch!(@event_hints, type)}
    end)
  end

  defp selected_events(form) do
    form.source |> Ecto.Changeset.get_field(:webhook_events) |> Enum.map(&to_string/1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:apps}>
      <.back_link navigate={~p"/apps/#{@environment.app}/environments/#{@environment}"}>
        {@environment.app.name} / {@environment.name}
      </.back_link>

      <.header>
        Webhook para a aplicação
        <:subtitle>
          O Courier avisa cada evento (enviado, entregue, devolvido, aberto...) por POST nesta URL,
          assinado no header <code>Courier-Signature</code>. Deixe vazio para não enviar.
        </:subtitle>
      </.header>

      <.card :if={@revealed_secret} id="revealed-secret" class="space-y-3 p-4">
        <p class="font-semibold">
          Segredo de assinatura. Copie agora: ele não será mostrado de novo.
        </p>
        <code class="block text-sm break-all">{@revealed_secret}</code>
        <div class="flex justify-end">
          <.button
            variant="primary"
            navigate={~p"/apps/#{@environment.app}/environments/#{@environment}"}
          >
            Já copiei
          </.button>
        </div>
      </.card>

      <.card :if={is_nil(@revealed_secret)} class="p-4">
        <.form
          for={@form}
          id="webhook_form"
          phx-submit="save"
          class="grid gap-x-4 sm:grid-cols-2 xl:grid-cols-3"
        >
          <div class="col-span-full">
            <.input
              field={@form[:webhook_url]}
              type="url"
              label="URL"
              placeholder="https://app.exemplo.com.br/webhooks/courier"
            />
          </div>
          <fieldset class="col-span-full mb-2 space-y-2">
            <legend class="mb-1 text-xs text-neutral">Eventos enviados para a URL</legend>
            <input type="hidden" name="environment[webhook_events][]" value="" />
            <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
              <label
                :for={{type, label, hint} <- event_options()}
                class="flex cursor-pointer items-start gap-2 text-sm"
              >
                <input
                  type="checkbox"
                  name="environment[webhook_events][]"
                  value={type}
                  checked={type in selected_events(@form)}
                  class="checkbox checkbox-sm checkbox-primary mt-0.5"
                />
                <span>
                  <span class="font-semibold">{label}</span>
                  <code class="ml-1 text-xs text-neutral">email.{type}</code>
                  <span class="block text-xs text-neutral">{hint}</span>
                </span>
              </label>
            </div>
          </fieldset>
          <div class="col-span-full mt-2 flex flex-wrap items-center justify-end gap-2">
            <.button navigate={~p"/apps/#{@environment.app}/environments/#{@environment}"}>
              Cancelar
            </.button>
            <.button variant="primary" phx-disable-with="Salvando...">Salvar</.button>
          </div>
        </.form>
      </.card>
    </Layouts.app>
    """
  end
end
