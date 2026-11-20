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
     |> assign_form(Apps.change_email_config(config))}
  end

  @impl true
  def handle_event("validate", %{"channel_config" => params}, socket) do
    changeset = Apps.change_email_config(socket.assigns.config, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"channel_config" => params}, socket) do
    environment = socket.assigns.environment
    inbound_url = inbound_url(environment, params["provider"])

    case Apps.save_email_config(environment, params, inbound_url) do
      {:ok, config} ->
        {:noreply,
         socket
         |> put_flash(flash_kind(config), saved_message(config))
         |> push_navigate(to: ~p"/apps/#{environment.app}/environments/#{environment}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp inbound_url(environment, "brevo"), do: url(~p"/webhooks/brevo/#{environment}")
  defp inbound_url(environment, _provider), do: url(~p"/webhooks/postmark/#{environment}")

  defp assign_form(socket, changeset) do
    socket
    |> assign(:form, to_form(changeset))
    |> assign(:provider, Ecto.Changeset.get_field(changeset, :provider) || :postmark)
  end

  defp provider_options do
    Enum.map(ChannelConfig.providers(), &{ChannelConfig.provider_label(&1), &1})
  end

  defp flash_kind(config) do
    if ChannelConfig.webhook_error(config), do: :warning, else: :info
  end

  defp saved_message(config) do
    label = ChannelConfig.provider_label(config.provider)

    cond do
      not ChannelConfig.receives_events?(config) ->
        "Configuração salva."

      ChannelConfig.webhook_error(config) ->
        "Configuração salva, mas o webhook não foi cadastrado no #{label}."

      true ->
        "Configuração salva e webhook cadastrado no #{label}."
    end
  end

  defp token_label(:postmark), do: "Server API Token"
  defp token_label(:brevo), do: "API Key"
  defp token_label(_provider), do: "API Token"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active={:apps}>
      <.back_link navigate={~p"/apps/#{@environment.app}/environments/#{@environment}"}>
        {@environment.app.name} / {@environment.name}
      </.back_link>

      <.header>
        E-mail
        <:subtitle>Provider, credencial, remetente padrão e, no Postmark, rastreio.</:subtitle>
      </.header>

      <.card class="max-w-[720px] p-4">
        <.form
          for={@form}
          id="config_form"
          phx-change="validate"
          phx-submit="save"
          class="grid gap-x-4 sm:grid-cols-2"
        >
          <.input
            field={@form[:provider]}
            type="select"
            label="Provider"
            options={provider_options()}
          />
          <p
            :if={@provider == :mailtrap_sandbox}
            class="mb-2 self-end text-sm text-neutral sm:pb-2"
          >
            Sandbox: o e-mail fica na caixa de testes do Mailtrap e não chega ao destinatário.
          </p>
          <p :if={@provider == :brevo} class="mb-2 self-end text-sm text-neutral sm:pb-2">
            Rastreio de abertura e clique é ligado na conta do Brevo.
          </p>
          <div :if={@provider == :postmark} class="hidden sm:block"></div>
          <.input
            field={@form[:server_token]}
            type="password"
            label={token_label(@provider)}
            value=""
            autocomplete="new-password"
            placeholder={
              @config.server_token_hint && @config.provider == @provider &&
                "••••#{@config.server_token_hint} (deixe vazio para manter)"
            }
          />
          <.input
            :if={@provider == :postmark}
            field={@form[:message_stream]}
            label="Message stream (transacional)"
          />
          <.input
            :if={@provider == :mailtrap_sandbox}
            field={@form[:mailtrap_inbox_id]}
            label="Inbox ID"
            inputmode="numeric"
          />
          <.input field={@form[:from_email]} type="email" label="E-mail do remetente" />
          <.input field={@form[:from_name]} label="Nome do remetente" />
          <.input
            :if={@provider == :postmark}
            field={@form[:track_opens]}
            type="checkbox"
            label="Rastrear aberturas"
          />
          <.input
            :if={@provider == :postmark}
            field={@form[:track_links]}
            type="checkbox"
            label="Rastrear cliques"
          />
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
