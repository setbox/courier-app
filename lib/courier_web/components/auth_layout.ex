defmodule CourierWeb.AuthLayout do
  use CourierWeb, :html

  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def auth_layout(assigns) do
    ~H"""
    <div class="grid min-h-screen bg-base-100 lg:grid-cols-[30fr_70fr]">
      <div class="flex items-center justify-center px-4 py-10">
        <div class="w-full max-w-sm space-y-8">
          <.link navigate={~p"/"} class="flex items-center gap-2.5">
            <img src={~p"/images/logo.svg"} alt="" class="h-7 w-auto" />
            <span class="text-xl font-bold">Courier</span>
          </.link>

          {render_slot(@inner_block)}
        </div>
      </div>

      <div class="relative hidden overflow-hidden bg-base-200 lg:block" aria-hidden="true">
        <picture>
          <source
            type="image/webp"
            srcset={"#{~p"/images/courier-1100.webp"} 1100w, #{~p"/images/courier-1600.webp"} 1600w"}
            sizes="70vw"
          />
          <img
            src={~p"/images/courier-1600.jpg"}
            srcset={"#{~p"/images/courier-1100.jpg"} 1100w, #{~p"/images/courier-1600.jpg"} 1600w"}
            sizes="70vw"
            alt=""
            class="absolute inset-0 size-full object-cover"
          />
        </picture>

        <div class="absolute inset-0 hidden bg-base-100/40 [[data-theme=dark]_&]:block"></div>
      </div>
    </div>

    <CourierWeb.Layouts.flash_group flash={@flash} />
    """
  end

  attr :show, :list, required: true

  def auth_links(assigns) do
    links =
      links()
      |> Enum.filter(fn {key, _, _} -> key in assigns.show end)
      |> Enum.with_index()

    assigns = assign(assigns, :links, links)

    ~H"""
    <p class="text-center text-sm text-base-content/60">
      <span :for={{{_key, label, path}, index} <- @links}>
        <span :if={index > 0} class="px-1 text-base-content/40">·</span>
        <.link navigate={path} class="link">{label}</.link>
      </span>
    </p>
    """
  end

  defp links do
    [
      {:login, "Entrar", ~p"/login"},
      {:reset, "Esqueci minha senha", ~p"/reset-password"},
      {:confirm, "Não recebi a confirmação", ~p"/confirm"}
    ]
  end

  def google_button(assigns) do
    assigns = assign(assigns, :configured, Courier.Connectors.Google.configured?())

    ~H"""
    <div :if={@configured} class="space-y-4">
      <a href={~p"/auth/google"} class="btn btn-outline w-full gap-2">
        <.google_mark /> Continuar com o Google
      </a>

      <div class="flex items-center gap-3 text-xs text-base-content/50">
        <span class="h-px flex-1 bg-base-300"></span> ou <span class="h-px flex-1 bg-base-300"></span>
      </div>
    </div>
    """
  end

  defp google_mark(assigns) do
    ~H"""
    <svg class="size-4" viewBox="0 0 48 48" aria-hidden="true">
      <path
        fill="#EA4335"
        d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
      />
      <path
        fill="#4285F4"
        d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
      />
      <path
        fill="#FBBC05"
        d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"
      />
      <path
        fill="#34A853"
        d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
      />
    </svg>
    """
  end
end
