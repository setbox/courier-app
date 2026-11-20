defmodule CourierWeb.Layouts do
  use CourierWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :active, :atom, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :items, nav_items())

    ~H"""
    <div class="flex min-h-screen">
      <nav
        class="sticky top-0 hidden h-screen w-[5.5rem] shrink-0 flex-col items-center gap-0.5 overflow-y-auto border-r border-base-300 bg-base-200 py-3 md:flex"
        aria-label="Principal"
      >
        <.link
          navigate={~p"/"}
          class="mb-2 flex size-12 items-center justify-center"
          aria-label="Courier, aplicações"
        >
          <img src={~p"/images/logo.svg"} alt="" class="h-8 w-auto" />
        </.link>
        <.link
          :for={{key, label, path, icon} <- @items}
          navigate={path}
          class="group flex w-20 flex-col items-center gap-1 py-1"
          aria-current={@active == key && "page"}
        >
          <span class={[
            "flex h-8 w-14 items-center justify-center rounded-full transition-colors",
            if(@active == key,
              do: "bg-accent text-accent-content",
              else: "group-hover:bg-accent/10 group-hover:text-accent"
            )
          ]}>
            <.icon name={icon} class="size-5" />
          </span>
          <span class={["text-[0.6875rem] leading-tight", @active == key && "font-bold"]}>
            {label}
          </span>
        </.link>
      </nav>

      <div class="flex min-w-0 flex-1 flex-col">
        <header class="sticky top-0 z-30 flex h-12 items-center justify-between gap-4 border-b border-base-300 bg-base-100 px-4 sm:px-6">
          <div class="flex items-center gap-2">
            <div class="dropdown md:hidden">
              <div
                tabindex="0"
                role="button"
                class="btn btn-ghost btn-square"
                aria-label="Menu"
              >
                <.icon name="hero-bars-3" class="size-5" />
              </div>
              <ul
                tabindex="0"
                class="dropdown-content menu z-40 mt-2 w-60 rounded-box border border-base-300 bg-base-100 p-2 shadow-lg"
              >
                <li :for={{key, label, path, icon} <- @items}>
                  <.link navigate={path} class={@active == key && "menu-active"}>
                    <.icon name={icon} class="size-4" /> {label}
                  </.link>
                </li>
              </ul>
            </div>
            <.link navigate={~p"/"} class="flex items-center gap-2.5">
              <img src={~p"/images/logo.svg"} alt="" class="h-6 w-auto md:hidden" />
              <span class="text-base font-semibold">Courier</span>
            </.link>
          </div>
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
        <main class="min-w-0 flex-1 px-4 py-6 sm:px-6">
          <div class="flex max-w-[1280px] flex-col gap-4">
            {render_slot(@inner_block)}
          </div>
        </main>
      </div>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  defp nav_items do
    [
      {:apps, "Aplicações", ~p"/", "hero-squares-2x2"},
      {:emails, "E-mails", ~p"/emails", "hero-envelope"},
      {:providers, "Providers", ~p"/providers", "hero-server-stack"}
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
