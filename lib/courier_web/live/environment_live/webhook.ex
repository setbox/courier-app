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
      {:ok, _environment, nil} ->
        {:noreply,
         socket
         |> put_flash(:info, "Webhook salvo.")
         |> push_navigate(to: ~p"/apps/#{environment.app}/environments/#{environment}")}

      {:ok, updated, secret} ->
        {:noreply,
         socket
         |> assign(:environment, %{updated | app: environment.app})
         |> assign(:form, to_form(Apps.change_webhook(updated)))
         |> assign(:revealed_secret, secret)
         |> put_flash(:info, "Webhook salvo.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
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

      <.card :if={@revealed_secret} id="revealed-secret" class="max-w-3xl space-y-3 p-6">
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

      <.card :if={is_nil(@revealed_secret)} class="max-w-3xl p-6">
        <.form for={@form} id="webhook_form" phx-submit="save">
          <.input
            field={@form[:webhook_url]}
            type="url"
            label="URL"
            placeholder="https://app.exemplo.com.br/webhooks/courier"
          />
          <div class="mt-4 flex flex-wrap items-center justify-end gap-2">
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
