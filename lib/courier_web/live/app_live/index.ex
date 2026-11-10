defmodule CourierWeb.AppLive.Index do
  use CourierWeb, :live_view

  alias Courier.Core.Apps

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Aplicações")
     |> assign(:apps, Apps.list_apps())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:apps}>
      <.header>
        Aplicações
        <:subtitle>Cada aplicação é um sistema que envia mensagens pelo Courier.</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/apps/new"}>Nova aplicação</.button>
        </:actions>
      </.header>

      <.empty_state :if={@apps == []} title="Nenhuma aplicação cadastrada.">
        Crie a primeira para cadastrar os ambientes e gerar o token de envio.
      </.empty_state>

      <.card :if={@apps != []} id="apps">
        <.link
          :for={app <- @apps}
          id={"app-#{app.id}"}
          navigate={~p"/apps/#{app}"}
          class="flex flex-wrap items-center gap-x-6 gap-y-2 border-t border-base-300 px-6 py-4 first:border-t-0 hover:bg-base-200"
        >
          <div class="min-w-0 flex-[1_1_320px] space-y-0.5">
            <span class="text-lg font-bold">{app.name}</span>
            <p class="text-[13px] text-neutral"><code>{app.slug}</code></p>
          </div>
          <span class="text-sm text-neutral">{environment_names(app)}</span>
          <.icon name="hero-chevron-right" class="size-5 text-neutral" />
        </.link>
      </.card>
    </Layouts.app>
    """
  end

  defp environment_names(%{environments: []}), do: "nenhum ambiente"

  defp environment_names(%{environments: environments}),
    do: Enum.map_join(environments, ", ", & &1.name)
end
