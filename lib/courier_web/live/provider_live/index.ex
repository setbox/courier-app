defmodule CourierWeb.ProviderLive.Index do
  use CourierWeb, :live_view

  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Providers")
     |> assign(:providers, ChannelConfig.providers())
     |> assign(:counts, Apps.count_environments_by_provider())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:providers}>
      <.header>
        Providers
        <:subtitle>Serviços que entregam os e-mails e os ambientes que usam cada um.</:subtitle>
      </.header>

      <.card id="providers">
        <.link
          :for={provider <- @providers}
          id={"provider-#{provider}"}
          navigate={~p"/providers/#{provider}"}
          class="flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-base-300 px-4 py-2.5 first:border-t-0 hover:bg-base-200"
        >
          <div class="min-w-0 flex-[1_1_320px] space-y-0.5">
            <span class="text-sm font-semibold">{ChannelConfig.provider_label(provider)}</span>
            <p class="text-xs text-neutral">{ChannelConfig.provider_description(provider)}</p>
          </div>
          <span class="text-sm text-neutral">{environment_count(@counts[provider])}</span>
          <.icon name="hero-chevron-right" class="size-5 text-neutral" />
        </.link>
      </.card>
    </Layouts.app>
    """
  end

  defp environment_count(nil), do: "nenhum ambiente"
  defp environment_count(1), do: "1 ambiente"
  defp environment_count(count), do: "#{count} ambientes"
end
