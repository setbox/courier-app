defmodule CourierWeb.DashboardLive do
  use CourierWeb, :live_view

  import CourierWeb.ChartComponents

  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig
  alias Courier.Core.Stats
  alias CourierWeb.Format

  @periods [
    {"7d", :days_7, "7 dias"},
    {"30d", :days_30, "30 dias"},
    {"12m", :months_12, "12 meses"}
  ]
  @months ~w(jan fev mar abr mai jun jul ago set out nov dez)

  @volume [
    %{key: :sent, label: "Enviados", class: "text-base-content"},
    %{key: :delivered, label: "Entregues", class: "text-success"}
  ]

  @problems [
    %{key: :failed, label: "Com erro", class: "text-error"},
    %{key: :not_found, label: "Não encontrado", class: "text-warning"},
    %{key: :bounced, label: "Devolvidos", class: "text-neutral", dashed: true},
    %{key: :spam, label: "Spam", class: "text-info"}
  ]

  @provider_classes %{postmark: "text-info", brevo: "text-warning", sandbox: "text-neutral"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Painel")
     |> assign(:environments, Apps.list_environments())
     |> assign(:hidden, MapSet.new())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {code, period, _label} = List.keyfind(@periods, params["period"], 0, Enum.at(@periods, 1))

    filters = %{
      environment_id: blank_to_nil(params["environment_id"]),
      category: category(params["category"])
    }

    series = Stats.series(period, filters)

    {:noreply,
     socket
     |> assign(:period, code)
     |> assign(:params, Map.take(params, ["environment_id", "category"]))
     |> assign(
       :filter_form,
       to_form(Map.take(params, ["environment_id", "category"]), as: :filters)
     )
     |> assign(:series, series)
     |> assign(:labels, Enum.map(series.buckets, &label(&1, series.bucket)))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    params =
      filters
      |> Map.take(["environment_id", "category"])
      |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.put("period", socket.assigns.period)

    {:noreply, push_patch(socket, to: ~p"/?#{params}")}
  end

  def handle_event("toggle_series", %{"key" => key}, socket) do
    key = String.to_existing_atom(key)
    hidden = socket.assigns.hidden

    hidden =
      if MapSet.member?(hidden, key),
        do: MapSet.delete(hidden, key),
        else: MapSet.put(hidden, key)

    {:noreply, assign(socket, :hidden, hidden)}
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp category("transactional"), do: :transactional
  defp category("marketing"), do: :marketing
  defp category(_value), do: nil

  defp label(date, :day), do: Calendar.strftime(date, "%d/%m")
  defp label(date, :month), do: Enum.at(@months, date.month - 1)

  defp with_values(definitions, points) do
    Enum.map(
      definitions,
      &Map.put(&1, :values, Enum.map(points, fn p -> Map.fetch!(p, &1.key) end))
    )
  end

  defp provider_series(by_provider, bucket_count) do
    Enum.map(ChannelConfig.providers(), fn provider ->
      %{
        key: provider,
        label: ChannelConfig.provider_label(provider),
        class: Map.fetch!(@provider_classes, provider),
        dashed: provider == :sandbox,
        values: Map.get(by_provider, provider, List.duplicate(0, bucket_count))
      }
    end)
  end

  defp kpis(totals) do
    [
      {"Enviados", :sent, "text-base-content", "aceitos pelo provider"},
      {"Entregues", :delivered, "text-success", nil},
      {"Com erro", :failed, "text-error", nil},
      {"Não encontrado", :not_found, "text-warning", nil},
      {"Devolvidos", :bounced, "text-neutral", nil},
      {"Spam", :spam, "text-info", nil}
    ]
    |> Enum.map(fn {label, key, class, note} ->
      %{
        label: label,
        class: class,
        value: Format.number(Map.fetch!(totals, key)),
        share: note || "#{Format.percent(Map.fetch!(totals, key), totals.sent)} dos enviados"
      }
    end)
  end

  defp subtitle("7d"), do: "Últimos 7 dias, por dia"
  defp subtitle("30d"), do: "Últimos 30 dias, por dia"
  defp subtitle("12m"), do: "Últimos 12 meses, por mês"

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:periods, @periods)
      |> assign(:volume, with_values(@volume, assigns.series.points))
      |> assign(:problems, with_values(@problems, assigns.series.points))
      |> assign(:providers, provider_series(assigns.series.by_provider, length(assigns.labels)))
      |> assign(:kpis, kpis(assigns.series.totals))

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:dashboard}>
      <.header>
        Painel
        <:subtitle>{subtitle(@period)}</:subtitle>
        <:actions>
          <.form
            for={@filter_form}
            id="dashboard_filters"
            phx-change="filter"
            class="flex flex-wrap items-center gap-2"
          >
            <select name="filters[environment_id]" class="select w-56" aria-label="Ambiente">
              <option value="">Todos os ambientes</option>
              <option
                :for={env <- @environments}
                value={env.id}
                selected={@params["environment_id"] == env.id}
              >
                {env.app.name} / {env.name}
              </option>
            </select>
            <select name="filters[category]" class="select w-44" aria-label="Categoria">
              <option value="">Todas as categorias</option>
              <option value="transactional" selected={@params["category"] == "transactional"}>
                Transacional
              </option>
              <option value="marketing" selected={@params["category"] == "marketing"}>
                Marketing
              </option>
            </select>
          </.form>
          <div
            role="group"
            aria-label="Período"
            class="flex gap-0.5 rounded-box border border-base-300 bg-base-100 p-[3px]"
          >
            <.link
              :for={{code, _period, label} <- @periods}
              patch={~p"/?#{Map.put(@params, "period", code)}"}
              aria-current={code == @period && "true"}
              class={[
                "flex h-[30px] items-center rounded-field px-3.5 text-[13px] font-semibold",
                if(code == @period,
                  do: "bg-primary text-primary-content",
                  else: "text-neutral hover:bg-base-200"
                )
              ]}
            >
              {label}
            </.link>
          </div>
        </:actions>
      </.header>

      <div id="kpis" class="grid gap-4 sm:grid-cols-3 xl:grid-cols-6">
        <.card :for={k <- @kpis} class="flex flex-col gap-1.5 p-4">
          <span class="flex items-center gap-2 text-xs font-semibold text-neutral">
            <span class={["size-2 rounded-full bg-current", k.class]} />{k.label}
          </span>
          <span class="tabular text-[26px] leading-tight font-semibold">{k.value}</span>
          <span class="tabular text-xs text-neutral">{k.share}</span>
        </.card>
      </div>

      <.card class="space-y-3 p-4">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="text-base font-semibold">Volume de envio</h2>
            <p class="text-xs text-neutral">Aceitos pelo provider e entregues ao destinatário</p>
          </div>
          <.chart_legend series={@volume} hidden={@hidden} />
        </div>
        <.line_chart
          id="chart-volume"
          label="Gráfico de linha: enviados e entregues no período"
          labels={@labels}
          series={@volume}
          hidden={@hidden}
        />
      </.card>

      <.card class="space-y-3 p-4">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="text-base font-semibold">Problemas de entrega</h2>
            <p class="text-xs text-neutral">
              Recusa do provider, endereço não encontrado, outras devoluções e marcação como spam
            </p>
          </div>
          <.chart_legend series={@problems} hidden={@hidden} />
        </div>
        <.line_chart
          id="chart-problems"
          label="Gráfico de linha: com erro, não encontrado, devolvidos e spam no período"
          labels={@labels}
          series={@problems}
          hidden={@hidden}
          height={220}
        />
      </.card>

      <.card class="space-y-3 p-4">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="text-base font-semibold">Por provider</h2>
            <p class="text-xs text-neutral">
              E-mails enviados por provider; o total do período vai na legenda
            </p>
          </div>
          <.chart_legend
            series={@providers}
            hidden={@hidden}
            totals={Map.new(@providers, &{&1.key, Enum.sum(&1.values)})}
          />
        </div>
        <.line_chart
          id="chart-providers"
          label="Gráfico de linha: enviados por provider no período"
          labels={@labels}
          series={@providers}
          hidden={@hidden}
          height={220}
        />
      </.card>
    </Layouts.app>
    """
  end
end
