defmodule CourierWeb.UserLive.Confirmation do
  use CourierWeb, :live_view

  import CourierWeb.AuthLayout

  alias Courier.Core.Accounts

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Confirmação")
     |> assign(:token, params["token"])
     |> assign(:trigger_submit, false)
     |> assign(:form, to_form(%{"email" => ""}, as: "user"))
     |> confirm_when_connected(params["token"])}
  end

  defp confirm_when_connected(socket, token) when is_binary(token) do
    if connected?(socket), do: send(self(), :confirm)
    socket
  end

  defp confirm_when_connected(socket, _token), do: socket

  @impl true
  def handle_info(:confirm, socket), do: {:noreply, assign(socket, :trigger_submit, true)}

  @impl true
  def handle_event("resend", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(user, &url(~p"/confirm/#{&1}"))
    end

    {:noreply,
     socket
     |> put_flash(:info, "Se este e-mail tiver conta pendente, o link chega em instantes.")
     |> push_navigate(to: ~p"/login")}
  end

  @impl true
  def render(%{token: token} = assigns) when is_binary(token) do
    ~H"""
    <.auth_layout flash={@flash}>
      <.header>
        Confirmando seu e-mail
        <:subtitle>Um instante, já levamos você para o Courier.</:subtitle>
      </.header>

      <form
        id="confirm-form"
        action={~p"/confirm"}
        method="post"
        phx-trigger-action={@trigger_submit}
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input type="hidden" name="token" value={@token} />
        <noscript>
          <div class="flex justify-end">
            <button type="submit" class="btn btn-primary">Confirmar meu e-mail</button>
          </div>
        </noscript>
      </form>
    </.auth_layout>
    """
  end

  def render(assigns) do
    ~H"""
    <.auth_layout flash={@flash}>
      <.header>
        Reenviar confirmação
        <:subtitle>
          O link de confirmação vale por 7 dias e só funciona uma vez. Informe seu e-mail que
          mandamos outro.
        </:subtitle>
      </.header>

      <.form for={@form} id="resend_form" phx-submit="resend" class="space-y-4">
        <.input
          field={@form[:email]}
          type="email"
          label="E-mail"
          autocomplete="username"
          required
          phx-mounted={JS.focus()}
        />
        <div class="flex justify-end">
          <.button variant="primary" phx-disable-with="Enviando...">Reenviar link</.button>
        </div>
      </.form>

      <.auth_links show={[:login, :reset]} />
    </.auth_layout>
    """
  end
end
