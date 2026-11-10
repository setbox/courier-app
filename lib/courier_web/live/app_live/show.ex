defmodule CourierWeb.AppLive.Show do
  use CourierWeb, :live_view

  alias Courier.Core.Apps

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    app = Apps.get_app!(id)

    {:ok,
     socket
     |> assign(:page_title, app.name)
     |> assign(:app, app)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:apps}>
      <.link
        navigate={~p"/"}
        class="flex items-center gap-1 text-sm font-semibold text-neutral hover:text-primary"
      >
        <.icon name="hero-chevron-left-mini" class="size-4" /> Aplicações
      </.link>

      <.header>
        {@app.name}
        <:subtitle>Identificador <code>{@app.slug}</code></:subtitle>
        <:actions>
          <.button navigate={~p"/apps/#{@app}/edit"}>Editar</.button>
          <.button variant="primary" navigate={~p"/apps/#{@app}/environments/new"}>
            Novo ambiente
          </.button>
        </:actions>
      </.header>

      <.empty_state :if={@app.environments == []} title="Nenhum ambiente ainda.">
        Cada ambiente tem o seu token, a sua configuração de e-mail e o seu webhook.
      </.empty_state>

      <.card :if={@app.environments != []} id="environments">
        <.link
          :for={env <- @app.environments}
          id={"environment-#{env.id}"}
          navigate={~p"/apps/#{@app}/environments/#{env}"}
          class="flex flex-wrap items-center gap-x-6 gap-y-2 border-t border-base-300 px-6 py-4 first:border-t-0 hover:bg-base-200"
        >
          <div class="min-w-0 flex-[1_1_240px] space-y-0.5">
            <span class="text-lg font-bold">{env.name}</span>
            <p class="text-[13px] text-neutral"><code>{env.slug}</code></p>
          </div>
          <.pill :if={env.client_token_hint} tone={:ok}>cl_…{env.client_token_hint}</.pill>
          <.pill :if={is_nil(env.client_token_hint)} tone={:pending}>sem token</.pill>
          <.icon name="hero-chevron-right" class="size-5 text-neutral" />
        </.link>
      </.card>
    </Layouts.app>
    """
  end
end
