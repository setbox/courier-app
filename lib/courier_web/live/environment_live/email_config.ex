defmodule CourierWeb.EnvironmentLive.EmailConfig do
  use CourierWeb, :live_view

  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig

  @impl true
  def mount(%{"app_id" => app_id, "id" => id}, _session, socket) do
    environment = Apps.get_environment!(app_id, id)
    config = Apps.email_config(environment) || %ChannelConfig{}

    {:ok,
     socket
     |> assign(:page_title, "E-mail · #{environment.name}")
     |> assign(:environment, environment)
     |> assign(:config, config)
     |> assign(:form, to_form(Apps.change_email_config(config)))}
  end

  @impl true
  def handle_event("validate", %{"channel_config" => params}, socket) do
    changeset = Apps.change_email_config(socket.assigns.config, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"channel_config" => params}, socket) do
    environment = socket.assigns.environment
    inbound_url = url(~p"/webhooks/postmark/#{environment}")

    case Apps.save_email_config(environment, params, inbound_url) do
      {:ok, config} ->
        {:noreply,
         socket
         |> put_flash(flash_kind(config), saved_message(config))
         |> push_navigate(to: ~p"/apps/#{environment.app}/environments/#{environment}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp flash_kind(%ChannelConfig{postmark_webhook_error: nil}), do: :info
  defp flash_kind(%ChannelConfig{}), do: :warning

  defp saved_message(%ChannelConfig{postmark_webhook_error: nil}),
    do: "Configuração salva e webhook cadastrado no Postmark."

  defp saved_message(%ChannelConfig{}),
    do: "Configuração salva, mas o webhook não foi cadastrado no Postmark."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:apps}>
      <.back_link navigate={~p"/apps/#{@environment.app}/environments/#{@environment}"}>
        {@environment.app.name} / {@environment.name}
      </.back_link>

      <.header>
        E-mail · Postmark
        <:subtitle>Credencial do server do Postmark, remetente padrão e rastreio.</:subtitle>
      </.header>

      <.card class="max-w-3xl p-6">
        <.form
          for={@form}
          id="config_form"
          phx-change="validate"
          phx-submit="save"
          class="grid gap-x-4 sm:grid-cols-2"
        >
          <.input
            field={@form[:server_token]}
            type="password"
            label="Server API Token"
            value=""
            autocomplete="off"
            placeholder={
              @config.server_token_hint &&
                "••••#{@config.server_token_hint} (deixe vazio para manter)"
            }
          />
          <.input field={@form[:message_stream]} label="Message stream (transacional)" />
          <.input field={@form[:from_email]} type="email" label="E-mail do remetente" />
          <.input field={@form[:from_name]} label="Nome do remetente" />
          <.input field={@form[:track_opens]} type="checkbox" label="Rastrear aberturas" />
          <.input field={@form[:track_links]} type="checkbox" label="Rastrear cliques" />
          <div class="mt-4 flex flex-wrap items-center justify-end gap-2 sm:col-span-2">
            <.button navigate={~p"/apps/#{@environment.app}/environments/#{@environment}"}>
              Cancelar
            </.button>
            <.button variant="primary" phx-disable-with="Salvando...">Salvar</.button>
          </div>
        </.form>
      </.card>
    </Layouts.app>
    """
  end
end
