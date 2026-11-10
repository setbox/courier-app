defmodule CourierWeb.UserLive.Login do
  use CourierWeb, :live_view

  import CourierWeb.AuthLayout

  @impl true
  def mount(params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    {:ok,
     socket
     |> assign(:page_title, "Entrar")
     |> assign(
       :return_to,
       socket.assigns.current_scope && CourierWeb.UserAuth.local_path(params["return_to"])
     )
     |> assign(:form, to_form(%{"email" => email}, as: "user"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_layout flash={@flash}>
      <.header>
        {if @current_scope, do: "Confirme seu acesso", else: "Entrar"}
        <:subtitle :if={@current_scope}>
          Por segurança, entre de novo para continuar esta ação.
        </:subtitle>
        <:subtitle :if={is_nil(@current_scope)}>
          Ainda não tem conta?
          <.link navigate={~p"/register"} class="link link-primary">Criar conta</.link>
        </:subtitle>
      </.header>

      <div :if={local_mail_adapter?()} class="alert alert-info">
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <p class="text-sm">
          Ambiente de desenvolvimento: os e-mails ficam em <.link
            href="/dev/mailbox"
            class="underline"
          >/dev/mailbox</.link>.
        </p>
      </div>

      <.google_button />

      <.form for={@form} id="login_form" action={~p"/login"} class="space-y-4">
        <input :if={@return_to} type="hidden" name="user[return_to]" value={@return_to} />
        <.input
          field={@form[:email]}
          type="email"
          label="E-mail"
          autocomplete="username"
          spellcheck="false"
          readonly={!!@current_scope}
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Senha"
          autocomplete="current-password"
          required
        />
        <label class="label cursor-pointer gap-2 text-sm">
          <input type="checkbox" name="user[remember_me]" value="true" class="checkbox checkbox-sm" />
          Manter conectado
        </label>

        <div class="flex justify-end">
          <.button variant="primary" phx-disable-with="Entrando...">Entrar</.button>
        </div>
      </.form>

      <.auth_links show={[:reset, :confirm]} />
    </.auth_layout>
    """
  end

  defp local_mail_adapter? do
    Application.get_env(:courier, Courier.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
