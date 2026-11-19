defmodule CourierWeb.ProviderLive.Show do
  use CourierWeb, :live_view

  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig

  @impl true
  def mount(%{"provider" => param}, _session, socket) do
    provider =
      Enum.find(ChannelConfig.providers(), &(Atom.to_string(&1) == param)) ||
        raise Ecto.NoResultsError, queryable: ChannelConfig

    {:ok,
     socket
     |> assign(:page_title, ChannelConfig.provider_label(provider))
     |> assign(:provider, provider)
     |> assign(:environments, Apps.list_environments_using(provider))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:providers}>
      <.back_link navigate={~p"/providers"}>Providers</.back_link>

      <.header>
        {ChannelConfig.provider_label(@provider)}
        <:subtitle>{ChannelConfig.provider_description(@provider)}</:subtitle>
      </.header>

      <.empty_state :if={@environments == []} title="Nenhum ambiente usa este provider.">
        Escolha o provider na configuração de e-mail do ambiente.
      </.empty_state>

      <.card :if={@environments != []} id="environments">
        <.link
          :for={environment <- @environments}
          id={"environment-#{environment.id}"}
          navigate={~p"/apps/#{environment.app}/environments/#{environment}"}
          class="flex flex-wrap items-center gap-x-6 gap-y-2 border-t border-base-300 px-6 py-4 first:border-t-0 hover:bg-base-200"
        >
          <div class="min-w-0 flex-[1_1_320px] space-y-0.5">
            <span class="text-lg font-bold">{environment.app.name} / {environment.name}</span>
            <p class="text-[13px] text-neutral"><code>{environment.slug}</code></p>
          </div>
          <.icon name="hero-chevron-right" class="size-5 text-neutral" />
        </.link>
      </.card>
    </Layouts.app>
    """
  end
end
