defmodule CourierWeb.UserLive.ForgotPassword do
  use CourierWeb, :live_view

  import CourierWeb.AuthLayout

  alias Courier.Core.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Esqueci minha senha")
     |> assign(:form, to_form(%{"email" => ""}, as: "user"))}
  end

  @impl true
  def handle_event("send", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(user, &url(~p"/reset-password/#{&1}"))
    end

    {:noreply,
     socket
     |> put_flash(:info, "Se este e-mail tiver conta, o link de redefinição chega em instantes.")
     |> push_navigate(to: ~p"/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_layout flash={@flash}>
      <.header>
        Esqueci minha senha
        <:subtitle>Mandamos um link para você escolher uma nova. Ele vale por 24 horas.</:subtitle>
      </.header>

      <.form for={@form} id="forgot_form" phx-submit="send" class="space-y-4">
        <.input
          field={@form[:email]}
          type="email"
          label="E-mail"
          autocomplete="username"
          required
          phx-mounted={JS.focus()}
        />
        <div class="flex justify-end">
          <.button variant="primary" phx-disable-with="Enviando...">Enviar link</.button>
        </div>
      </.form>

      <.auth_links show={[:login, :confirm]} />
    </.auth_layout>
    """
  end
end
