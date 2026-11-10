defmodule CourierWeb.AppLive.Form do
  use CourierWeb, :live_view

  alias Courier.Core.Apps
  alias Courier.Core.Apps.App

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    app = %App{}

    socket
    |> assign(:page_title, "Nova aplicação")
    |> assign(:app, app)
    |> assign(:form, to_form(Apps.change_app(app)))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    app = Apps.get_app!(id)

    socket
    |> assign(:page_title, "Editar #{app.name}")
    |> assign(:app, app)
    |> assign(:form, to_form(Apps.change_app(app)))
  end

  @impl true
  def handle_event("validate", %{"app" => params}, socket) do
    changeset = Apps.change_app(socket.assigns.app, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"app" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Apps.create_app(params)
        :edit -> Apps.update_app(socket.assigns.app, Map.take(params, ["name"]))
      end

    case result do
      {:ok, app} ->
        {:noreply,
         socket
         |> put_flash(:info, "Aplicação salva.")
         |> push_navigate(to: ~p"/apps/#{app}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:apps}>
      <.header>
        {@page_title}
        <:subtitle>O sistema que vai enviar mensagens pelo Courier.</:subtitle>
      </.header>

      <.card class="max-w-2xl p-6">
        <.form for={@form} id="app_form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} label="Nome" placeholder="Ex.: Jayio" required />
          <p :if={@live_action == :edit} class="mb-3 text-xs text-neutral">
            Identificador <code>{@app.slug}</code>: não muda ao renomear.
          </p>
          <div class="mt-4 flex flex-wrap items-center justify-end gap-2">
            <.button navigate={if @app.id, do: ~p"/apps/#{@app}", else: ~p"/"}>Cancelar</.button>
            <.button variant="primary" phx-disable-with="Salvando...">Salvar</.button>
          </div>
        </.form>
      </.card>
    </Layouts.app>
    """
  end
end
