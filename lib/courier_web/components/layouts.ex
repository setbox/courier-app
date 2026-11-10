defmodule CourierWeb.Layouts do
  use CourierWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :active, :atom, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="sticky top-0 z-30 flex h-14 items-center justify-between gap-4 border-b border-base-300 bg-base-100 px-4 sm:px-6">
      <.link navigate={~p"/"} class="flex items-center gap-2.5">
        <img src={~p"/images/logo.svg"} alt="" class="h-6 w-auto" />
        <span class="text-lg font-bold">Courier</span>
      </.link>
      <div class="flex items-center gap-3">
        <.theme_toggle />
        <div :if={@current_scope} class="dropdown dropdown-end">
          <div
            tabindex="0"
            role="button"
            aria-label="Menu da conta"
            class="flex min-h-9 cursor-pointer items-center gap-2 rounded-lg px-2 hover:bg-base-200"
          >
            <span class="flex size-7 items-center justify-center rounded-full bg-primary text-xs font-bold text-white uppercase">
              {String.first(@current_scope.user.email)}
            </span>
            <span class="hidden max-w-56 truncate text-sm font-semibold sm:inline">
              {@current_scope.user.email}
            </span>
            <.icon name="hero-chevron-down-mini" class="size-4 text-neutral" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu z-40 mt-2 w-60 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
          >
            <li><.link navigate={~p"/settings"}>Conta e senha</.link></li>
            <li><.link href={~p"/logout"} method="delete">Sair</.link></li>
          </ul>
        </div>
      </div>
    </header>
    <div class="min-h-[calc(100vh-3.5rem)] lg:grid lg:grid-cols-[232px_minmax(0,1fr)]">
      <aside class="border-b border-base-300 bg-base-100 px-4 py-5 lg:sticky lg:top-14 lg:h-[calc(100vh-3.5rem)] lg:overflow-y-auto lg:border-r lg:border-b-0">
        <nav aria-label="Principal" class="flex flex-col gap-0.5">
          <.nav_link :for={{key, label, path} <- nav_items()} active={@active == key} path={path}>
            {label}
          </.nav_link>
        </nav>
      </aside>
      <main class="min-w-0 px-4 py-8 sm:px-10">
        <div class="flex flex-col gap-6">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  attr :active, :boolean, default: false
  attr :path, :string, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@path}
      aria-current={@active && "page"}
      class={[
        "flex min-h-11 items-center rounded-lg px-3 text-sm font-semibold transition-colors",
        if(@active, do: "bg-primary/10 text-primary", else: "hover:bg-base-200")
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp nav_items do
    [
      {:apps, "Aplicações", ~p"/"},
      {:emails, "E-mails", ~p"/emails"}
    ]
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="toast toast-bottom toast-end z-50">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Sem conexão"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Tentando reconectar
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Algo deu errado"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Tentando reconectar
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
