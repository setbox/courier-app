defmodule CourierWeb.UserLive.Registration do
  use CourierWeb, :live_view

  require Logger

  import CourierWeb.AuthLayout

  alias Courier.Core.Accounts
  alias Courier.Core.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Criar conta")
     |> assign_form(Accounts.change_user_registration(%User{}))}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        case Accounts.deliver_user_confirmation_instructions(user, &url(~p"/confirm/#{&1}")) do
          {:ok, _email} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Conta criada. Enviamos um e-mail de confirmação para #{user.email}: clique no link para entrar."
             )
             |> push_navigate(to: ~p"/login")}

          {:error, reason} ->
            Logger.error("confirmação não enviada para #{user.email}: #{inspect(reason)}")

            {:noreply,
             socket
             |> put_flash(
               :error,
               "Conta criada, mas o e-mail de confirmação não saiu. Peça o reenvio abaixo."
             )
             |> push_navigate(to: ~p"/confirm")}
        end

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset),
    do: assign(socket, :form, to_form(changeset, as: "user"))

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_layout flash={@flash}>
      <.header>
        Criar conta
        <:subtitle>
          Já tem conta? <.link navigate={~p"/login"} class="link link-primary">Entrar</.link>
        </:subtitle>
      </.header>

      <.google_button />

      <.form
        for={@form}
        id="registration_form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input
          field={@form[:email]}
          type="email"
          label="E-mail"
          autocomplete="username"
          spellcheck="false"
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Senha"
          autocomplete="new-password"
          required
        />
        <p class="text-xs text-base-content/60">Pelo menos 8 caracteres.</p>

        <div class="flex justify-end">
          <.button variant="primary" phx-disable-with="Criando...">Criar conta</.button>
        </div>
      </.form>

      <.auth_links show={[:confirm]} />
    </.auth_layout>
    """
  end
end
