defmodule CourierWeb.ChartComponents do
  use Phoenix.Component

  alias CourierWeb.Format

  @top 10
  @bottom 230
  @view_height 250

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :labels, :list, required: true
  attr :series, :list, required: true
  attr :hidden, :any, default: MapSet.new()
  attr :height, :integer, default: 240

  def line_chart(assigns) do
    visible = Enum.reject(assigns.series, &MapSet.member?(assigns.hidden, &1.key))
    max = visible |> Enum.flat_map(& &1.values) |> Enum.max(fn -> 0 end) |> ceiling()
    count = length(assigns.labels)

    assigns =
      assigns
      |> assign(:paths, Enum.map(visible, &Map.put(&1, :d, path(&1.values, max))))
      |> assign(:y_labels, y_labels(max, assigns.height))
      |> assign(:x_labels, x_labels(assigns.labels, count))

    ~H"""
    <div id={@id} class="flex gap-2">
      <div
        class="tabular relative flex-none text-[11px] text-neutral"
        style={"width: 48px; height: #{@height}px"}
        aria-hidden="true"
      >
        <span
          :for={y <- @y_labels}
          class="absolute right-0 -translate-y-1/2"
          style={"top: #{y.top}px"}
        >
          {y.text}
        </span>
      </div>
      <div class="flex min-w-0 flex-1 flex-col gap-1.5">
        <svg
          viewBox="0 0 1000 250"
          preserveAspectRatio="none"
          role="img"
          aria-label={@label}
          class="block w-full"
          style={"height: #{@height}px"}
        >
          <path
            d="M0 10H1000M0 65H1000M0 120H1000M0 175H1000M0 230H1000"
            class="stroke-base-300"
            stroke-width="1"
            vector-effect="non-scaling-stroke"
            fill="none"
          />
          <path
            :for={s <- @paths}
            d={s.d}
            class={s.class}
            stroke="currentColor"
            stroke-width="2"
            stroke-dasharray={if s[:dashed], do: "6 4"}
            stroke-linejoin="round"
            stroke-linecap="round"
            vector-effect="non-scaling-stroke"
            fill="none"
          />
        </svg>
        <div class="tabular relative h-4 text-[11px] text-neutral" aria-hidden="true">
          <span
            :for={x <- @x_labels}
            class={["absolute top-0 whitespace-nowrap", x.align]}
            style={"left: #{x.left}%"}
          >
            {x.text}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :series, :list, required: true
  attr :hidden, :any, default: MapSet.new()
  attr :totals, :map, default: %{}

  def chart_legend(assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <button
        :for={s <- @series}
        type="button"
        phx-click="toggle_series"
        phx-value-key={s.key}
        aria-pressed={to_string(not MapSet.member?(@hidden, s.key))}
        class={[
          "flex h-7 cursor-pointer items-center gap-1.5 rounded-full border border-base-300 bg-base-100 px-2.5 text-xs font-semibold",
          MapSet.member?(@hidden, s.key) && "text-neutral"
        ]}
      >
        <span class={[
          "h-[3px] w-3.5 rounded-sm bg-current",
          s.class,
          MapSet.member?(@hidden, s.key) && "opacity-35"
        ]} />
        {s.label}
        <span :if={Map.has_key?(@totals, s.key)} class="tabular font-medium text-neutral">
          {Format.number(Map.fetch!(@totals, s.key))}
        </span>
      </button>
    </div>
    """
  end

  defp ceiling(0), do: 4

  defp ceiling(value) do
    raw_step = value * 1.1 / 4
    magnitude = max(:math.pow(10, floor(:math.log10(raw_step))), 1)
    trunc(Float.ceil(raw_step / magnitude) * magnitude) * 4
  end

  defp path(values, max) do
    count = length(values)

    values
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {value, index} ->
      x = if count == 1, do: 0, else: index / (count - 1) * 1000
      y = @bottom - value / max * (@bottom - @top)
      "#{if index == 0, do: "M", else: "L"}#{Float.round(x * 1.0, 1)} #{Float.round(y * 1.0, 1)}"
    end)
  end

  defp y_labels(max, height) do
    Enum.map([0, 0.25, 0.5, 0.75, 1], fn fraction ->
      top = (@bottom - fraction * (@bottom - @top)) / @view_height * height
      %{text: Format.number(round(max * fraction)), top: Float.round(top, 1)}
    end)
  end

  defp x_labels(labels, count) do
    step = if count > 12, do: 5, else: 1

    labels
    |> Enum.with_index()
    |> Enum.map(fn {text, index} ->
      %{
        text: if(rem(index, step) == 0 or index == count - 1, do: text, else: ""),
        left: if(count == 1, do: 0, else: Float.round(index / (count - 1) * 100, 2)),
        align:
          cond do
            index == 0 -> ""
            index == count - 1 -> "-translate-x-full"
            true -> "-translate-x-1/2"
          end
      }
    end)
  end
end
