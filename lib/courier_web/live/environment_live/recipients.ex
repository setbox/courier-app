defmodule CourierWeb.EnvironmentLive.Recipients do
  use CourierWeb, :live_view

  alias Courier.Core.Apps

  @impl true
  def mount(%{"app_id" => app_id, "id" => id}, _session, socket) do
    environment = Apps.get_environment!(app_id, id)

    {:ok,
     socket
     |> assign(:page_title, "Destinatários · #{environment.name}")
     |> assign(:environment, environment)
     |> assign(:form, to_form(Apps.change_recipient_lists(environment), as: "recipients"))
     |> assign(:allowed_text, Enum.join(environment.allowed_recipients, "\n"))
     |> assign(:blocked_text, Enum.join(environment.blocked_recipients, "\n"))}
  end

  @impl true
  def handle_event("save", %{"recipients" => params}, socket) do
    environment = socket.assigns.environment

    case Apps.update_recipient_lists(environment, params) do
      {:ok, _environment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Listas de destinatários salvas.")
         |> push_navigate(to: ~p"/apps/#{environment.app}/environments/#{environment}")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: "recipients"))
         |> assign(:allowed_text, params["allowed_recipients"])
         |> assign(:blocked_text, params["blocked_recipients"])}
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
        Destinatários permitidos e bloqueados
        <:subtitle>
          Um por linha: e-mail exato (ana@exemplo.com.br) ou domínio inteiro (@setbox.com.br).
          Com a lista de permitidos preenchida, só ela recebe. Pedido com qualquer destinatário fora
          das regras é recusado inteiro, com o código <code>recipient_not_allowed</code>.
        </:subtitle>
      </.header>

      <.card class="max-w-3xl p-6">
        <.form
          for={@form}
          id="recipients_form"
          phx-submit="save"
          class="grid gap-x-4 sm:grid-cols-2"
        >
          <.input
            field={@form[:allowed_recipients]}
            type="textarea"
            label="Permitidos (whitelist)"
            value={@allowed_text}
            rows="8"
            placeholder="@setbox.com.br"
          />
          <.input
            field={@form[:blocked_recipients]}
            type="textarea"
            label="Bloqueados (blacklist)"
            value={@blocked_text}
            rows="8"
            placeholder="cliente.antigo@exemplo.com.br"
          />
          <div class="mt-4 flex flex-wrap items-center justify-end gap-2 sm:col-span-2">
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
