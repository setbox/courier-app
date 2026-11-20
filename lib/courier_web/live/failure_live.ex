defmodule CourierWeb.FailureLive do
  use CourierWeb, :live_view

  alias Courier.Core.{Apps, Emails, Stats}
  alias Courier.Core.Apps.ChannelConfig
  alias CourierWeb.Format

  @periods [
    {"7d", :days_7, "7 dias"},
    {"30d", :days_30, "30 dias"},
    {"12m", :months_12, "12 meses"}
  ]
  @page 50
  @badges %{
    failed: "badge-error",
    not_found: "badge-warning",
    bounced: "badge-neutral",
    spam: "badge-info"
  }

  @types [
    {"failed", :failed, "Com erro", "text-error"},
    {"not_found", :not_found, "Não encontrado", "text-warning"},
    {"bounced", :bounced, "Devolvidos", "text-neutral"},
    {"spam", :spam, "Spam", "text-info"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Falhas")
     |> assign(:environments, Apps.list_environments())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {code, period, _label} = List.keyfind(@periods, params["period"], 0, Enum.at(@periods, 1))
    type = Enum.find_value(@types, fn {key, atom, _, _} -> key == params["type"] && atom end)
    limit = parse_limit(params["limit"])

    filters = %{
      since: Stats.since(period),
      type: type,
      environment_id: blank_to_nil(params["environment_id"]),
      provider: provider(params["provider"]),
      q: blank_to_nil(params["q"])
    }

    counts = Emails.count_failures(Map.delete(filters, :type))
    failures = Emails.list_failures(filters, limit + 1)

    {:noreply,
     socket
     |> assign(:period, code)
     |> assign(:type, params["type"])
     |> assign(:params, Map.take(params, ["period", "type", "environment_id", "provider", "q"]))
     |> assign(
       :filter_form,
       to_form(Map.take(params, ["environment_id", "provider", "q"]), as: :filters)
     )
     |> assign(:counts, counts)
     |> assign(:total, if(type, do: Map.fetch!(counts, type), else: Enum.sum(Map.values(counts))))
     |> assign(:limit, limit)
     |> assign(:more?, length(failures) > limit)
     |> assign(:failures, Enum.take(failures, limit))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    params =
      socket.assigns.params
      |> Map.merge(Map.take(filters, ["environment_id", "provider", "q"]))
      |> Map.reject(fn {_key, value} -> value in [nil, ""] end)

    {:noreply, push_patch(socket, to: ~p"/falhas?#{params}")}
  end

  defp parse_limit(value) do
    case Integer.parse(value || "") do
      {n, ""} when n > 0 -> min(n, 500)
      _ -> @page
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp provider(value) do
    Enum.find(ChannelConfig.providers(), &(Atom.to_string(&1) == value))
  end

  defp type_label(type),
    do: Enum.find_value(@types, fn {_, atom, label, _} -> atom == type && label end)

  defp badge_class(type), do: Map.fetch!(@badges, type)

  defp chip_params(params, nil), do: Map.delete(params, "type")
  defp chip_params(params, key), do: Map.put(params, "type", key)

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:periods, @periods)
      |> assign(:types, @types)
      |> assign(:providers, ChannelConfig.providers())

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:failures}>
      <.header>
        Falhas
        <:subtitle>E-mails que não chegaram ao destinatário</:subtitle>
        <:actions>
          <div
            role="group"
            aria-label="Período"
            class="flex gap-0.5 rounded-box border border-base-300 bg-base-100 p-[3px]"
          >
            <.link
              :for={{code, _period, label} <- @periods}
              patch={~p"/falhas?#{Map.put(@params, "period", code)}"}
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

      <nav aria-label="Tipo de falha" class="flex flex-wrap gap-2">
        <.link
          patch={~p"/falhas?#{chip_params(@params, nil)}"}
          aria-current={is_nil(@type) && "true"}
          class={[
            "flex h-8 items-center gap-2 rounded-full border px-3 text-[13px] font-semibold",
            if(is_nil(@type),
              do: "border-primary bg-primary text-primary-content",
              else: "border-base-300 bg-base-100"
            )
          ]}
        >
          Todas
          <span class="tabular font-medium opacity-80">
            {Format.number(Enum.sum(Map.values(@counts)))}
          </span>
        </.link>
        <.link
          :for={{key, atom, label, class} <- @types}
          id={"type-#{key}"}
          patch={~p"/falhas?#{chip_params(@params, key)}"}
          aria-current={@type == key && "true"}
          class={[
            "flex h-8 items-center gap-2 rounded-full border px-3 text-[13px] font-semibold",
            if(@type == key,
              do: "border-primary bg-primary text-primary-content",
              else: "border-base-300 bg-base-100"
            )
          ]}
        >
          <span class={["size-2 rounded-full bg-current", @type != key && class]} />
          {label}
          <span class="tabular font-medium opacity-80">
            {Format.number(Map.fetch!(@counts, atom))}
          </span>
        </.link>
      </nav>

      <.card class="p-4">
        <.form
          for={@filter_form}
          id="failure_filters"
          phx-change="filter"
          class="grid gap-x-4 sm:grid-cols-2 xl:grid-cols-3"
        >
          <.input
            field={@filter_form[:environment_id]}
            type="select"
            label="Ambiente"
            prompt="Todos os ambientes"
            options={Enum.map(@environments, &{"#{&1.app.name} / #{&1.name}", &1.id})}
          />
          <.input
            field={@filter_form[:provider]}
            type="select"
            label="Provider"
            prompt="Todos os providers"
            options={Enum.map(@providers, &{ChannelConfig.provider_label(&1), &1})}
          />
          <.input
            field={@filter_form[:q]}
            type="search"
            label="Destinatário"
            placeholder="e-mail ou domínio"
            phx-debounce="300"
          />
        </.form>
      </.card>

      <.empty_state :if={@failures == []} title="Nenhuma falha no período.">
        Mude o período ou os filtros para ver outras falhas.
      </.empty_state>

      <.card :if={@failures != []} id="failures">
        <.link
          :for={f <- @failures}
          id={f.id}
          navigate={~p"/emails/#{f.email}"}
          class="flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-base-300 px-4 py-2.5 first:border-t-0 hover:bg-base-200"
        >
          <span class={[
            "badge badge-soft badge-sm w-32 justify-start gap-1.5 font-semibold",
            badge_class(f.type)
          ]}>
            <span class="size-1.5 rounded-full bg-current" />{type_label(f.type)}
          </span>
          <span class="flex min-w-0 flex-[1_1_260px] flex-col">
            <span class="truncate text-sm font-semibold">{f.email.subject}</span>
            <span class="truncate text-xs text-neutral">
              {f.address} · {f.email.environment.app.name} / {f.email.environment.name}<span :if={
                f.email.provider
              }> · {ChannelConfig.provider_label(f.email.provider)}</span>
            </span>
          </span>
          <code class="min-w-0 flex-[1_1_280px] truncate text-xs text-neutral">{f.reason}</code>
          <span class="tabular text-xs whitespace-nowrap text-neutral">
            {Format.short_datetime(f.at)}
          </span>
          <.icon name="hero-chevron-right" class="size-4 text-neutral" />
        </.link>
        <div class="flex flex-wrap items-center justify-between gap-3 border-t border-base-300 px-4 py-3">
          <span class="tabular text-xs text-neutral">
            Mostrando {Format.number(length(@failures))} de {Format.number(@total)}
          </span>
          <.button :if={@more?} patch={~p"/falhas?#{Map.put(@params, "limit", @limit + 50)}"}>
            Carregar mais
          </.button>
        </div>
      </.card>
    </Layouts.app>
    """
  end
end
