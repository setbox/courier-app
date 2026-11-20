defmodule CourierWeb.PanelComponents do
  use Phoenix.Component

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      class={["overflow-hidden rounded-box border border-base-300 bg-base-100", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :title, :string, required: true
  attr :class, :any, default: nil
  slot :subtitle
  slot :inner_block, required: true

  def card_section(assigns) do
    ~H"""
    <.card class={["space-y-4 p-4", @class]}>
      <div class="space-y-1">
        <h2 class="text-base font-semibold">{@title}</h2>
        <p :if={@subtitle != []} class="text-sm text-neutral">{render_slot(@subtitle)}</p>
      </div>
      {render_slot(@inner_block)}
    </.card>
    """
  end

  attr :navigate, :string, required: true
  slot :inner_block, required: true

  def back_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="flex items-center gap-1 text-sm font-semibold text-neutral hover:text-primary"
    >
      <CourierWeb.CoreComponents.icon name="hero-chevron-left-mini" class="size-4" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :title, :string, required: true
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <.card class="p-8 text-center">
      <p class="font-semibold">{@title}</p>
      <p :if={@inner_block != []} class="text-sm text-neutral">{render_slot(@inner_block)}</p>
    </.card>
    """
  end

  attr :tone, :atom, values: [:ok, :pending, :error, :neutral], required: true
  attr :rest, :global
  slot :inner_block, required: true

  def pill(assigns) do
    ~H"""
    <span
      class={["badge badge-soft badge-sm gap-1.5 font-semibold whitespace-nowrap", pill_tone(@tone)]}
      {@rest}
    >
      <span class="size-1.5 rounded-full bg-current" aria-hidden="true"></span>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp pill_tone(:ok), do: "badge-success"
  defp pill_tone(:pending), do: "badge-warning"
  defp pill_tone(:error), do: "badge-error"
  defp pill_tone(:neutral), do: "badge-neutral"
end
