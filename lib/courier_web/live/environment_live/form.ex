defmodule CourierWeb.EnvironmentLive.Form do
  use CourierWeb, :live_view

  alias Courier.Core.Apps
  alias Courier.Core.Apps.Environment

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, %{"app_id" => app_id}) do
    app = Apps.get_app!(app_id)
    environment = %Environment{app: app, app_id: app.id}

    socket
    |> assign(:page_title, "Novo ambiente")
    |> assign(:app, app)
    |> assign(:environment, environment)
    |> assign(:form, to_form(Apps.change_environment(environment)))
  end

  defp apply_action(socket, :edit, %{"app_id" => app_id, "id" => id}) do
    environment = Apps.get_environment!(app_id, id)

    socket
    |> assign(:page_title, "Editar #{environment.name}")
    |> assign(:app, environment.app)
    |> assign(:environment, environment)
    |> assign(:form, to_form(Apps.change_environment(environment)))
  end

  @impl true
  def handle_event("validate", %{"environment" => params}, socket) do
    changeset = Apps.change_environment(socket.assigns.environment, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"environment" => params}, socket) do
    result =
      case socket.assigns.live_action do
        :new -> Apps.create_environment(socket.assigns.app, params)
        :edit -> Apps.update_environment(socket.assigns.environment, Map.take(params, ["name"]))
      end

    case result do
      {:ok, environment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ambiente salvo.")
         |> push_navigate(to: ~p"/apps/#{socket.assigns.app}/environments/#{environment}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp cancel_path(%{environment: %Environment{id: nil}, app: app}), do: ~p"/apps/#{app}"

  defp cancel_path(%{environment: environment, app: app}),
    do: ~p"/apps/#{app}/environments/#{environment}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:apps}>
      <.back_link navigate={~p"/apps/#{@app}"}>{@app.name}</.back_link>

      <.header>
        {@page_title}
        <:subtitle>
          Ambiente de {@app.name}: local, dev, stage, prod ou o nome que fizer sentido.
        </:subtitle>
      </.header>

      <.card class="max-w-2xl p-6">
        <.form for={@form} id="environment_form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} label="Nome" placeholder="Ex.: prod" required />
          <p :if={@live_action == :edit} class="mb-3 text-xs text-neutral">
            Identificador <code>{@environment.slug}</code>: não muda ao renomear.
          </p>
          <div class="mt-4 flex flex-wrap items-center justify-end gap-2">
            <.button navigate={cancel_path(assigns)}>Cancelar</.button>
            <.button variant="primary" phx-disable-with="Salvando...">Salvar</.button>
          </div>
        </.form>
      </.card>
    </Layouts.app>
    """
  end
end
