defmodule CourierWeb.EmailLive.Index do
  use CourierWeb, :live_view

  alias Courier.Core.{Apps, Emails}
  alias CourierWeb.Format

  @filters ~w(environment_id status to)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "E-mails")
     |> assign(:environments, Apps.list_environments())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filters)
    {emails, next_cursor} = Emails.list_emails(to_keyword(filters))

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: "filters"))
     |> assign(:emails, emails)
     |> assign(:next_cursor, next_cursor)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    query = filters |> Map.take(@filters) |> Enum.reject(fn {_k, v} -> v == "" end)
    {:noreply, push_patch(socket, to: ~p"/emails?#{query}")}
  end

  def handle_event("more", _params, socket) do
    {emails, next_cursor} =
      Emails.list_emails(to_keyword(socket.assigns.filters), cursor: socket.assigns.next_cursor)

    {:noreply,
     socket
     |> assign(:emails, socket.assigns.emails ++ emails)
     |> assign(:next_cursor, next_cursor)}
  end

  defp to_keyword(filters) do
    Enum.map(filters, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  defp environment_options(environments) do
    [{"Todos os ambientes", ""} | Enum.map(environments, &{"#{&1.app.name} · #{&1.name}", &1.id})]
  end

  defp status_options do
    [
      {"Todos os status", ""}
      | Enum.map(Courier.Core.Emails.Email.statuses(), &{Format.email_status(&1), &1})
    ]
  end

  defp recipients(email) do
    email.recipients |> Enum.filter(&(&1.kind == :to)) |> Enum.map_join(", ", & &1.address)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:emails}>
      <.header>
        E-mails
        <:subtitle>Tudo o que as aplicações enviaram pelo Courier nos últimos 90 dias.</:subtitle>
      </.header>

      <.card class="p-6">
        <.form
          for={@filter_form}
          id="filter_form"
          phx-change="filter"
          phx-submit="filter"
          class="grid gap-x-4 sm:grid-cols-3"
        >
          <.input
            field={@filter_form[:environment_id]}
            type="select"
            label="Ambiente"
            options={environment_options(@environments)}
          />
          <.input
            field={@filter_form[:status]}
            type="select"
            label="Status"
            options={status_options()}
          />
          <.input field={@filter_form[:to]} type="email" label="Destinatário" phx-debounce="400" />
        </.form>
      </.card>

      <.empty_state :if={@emails == []} title="Nenhum e-mail encontrado." />

      <.card :if={@emails != []} id="emails">
        <.link
          :for={email <- @emails}
          id={"email-#{email.id}"}
          navigate={~p"/emails/#{email}"}
          class="flex flex-wrap items-center gap-x-6 gap-y-2 border-t border-base-300 px-6 py-4 first:border-t-0 hover:bg-base-200"
        >
          <div class="min-w-0 flex-[1_1_360px] space-y-0.5">
            <span class="block truncate font-bold">{email.subject}</span>
            <p class="truncate text-[13px] text-neutral">
              {recipients(email)} · {email.environment.app.name} / {email.environment.name}
            </p>
          </div>
          <span class="tabular text-sm text-neutral">{Format.datetime(email.inserted_at)}</span>
          <.pill tone={Format.tone(email.status)}>{Format.email_status(email.status)}</.pill>
          <.icon name="hero-chevron-right" class="size-5 text-neutral" />
        </.link>
      </.card>

      <div :if={@next_cursor} class="flex justify-center">
        <.button phx-click="more">Carregar mais</.button>
      </div>
    </Layouts.app>
    """
  end
end
