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
    <.card class={["space-y-4 p-6", @class]}>
      <div class="space-y-1">
        <h2 class="text-lg font-bold">{@title}</h2>
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
    <.card class="p-10 text-center">
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
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-bold whitespace-nowrap",
        pill_colors(@tone)
      ]}
      {@rest}
    >
      <span class={["size-1.5 rounded-full", pill_dot(@tone)]} aria-hidden="true"></span>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp pill_colors(:ok), do: "bg-success/12 text-success"
  defp pill_colors(:pending), do: "bg-warning/15 text-warning"
  defp pill_colors(:error), do: "bg-error/12 text-error"
  defp pill_colors(:neutral), do: "bg-base-300 text-neutral"

  defp pill_dot(:ok), do: "bg-success"
  defp pill_dot(:pending), do: "bg-warning"
  defp pill_dot(:error), do: "bg-error"
  defp pill_dot(:neutral), do: "bg-neutral"
end
