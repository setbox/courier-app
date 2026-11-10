defmodule CourierWeb.UserLive.ResetPassword do
  use CourierWeb, :live_view

  import CourierWeb.AuthLayout

  alias Courier.Core.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "O link de redefinição é inválido ou expirou.")
         |> push_navigate(to: ~p"/reset-password")}

      user ->
        {:ok,
         socket
         |> assign(:page_title, "Nova senha")
         |> assign(:user, user)
         |> assign(:form, to_form(Accounts.change_user_password(user, %{}, hash_password: false)))}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_password(params, hash_password: false)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, params) do
      {:ok, {_user, _expired_tokens}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Senha redefinida. Entre com a nova senha.")
         |> put_flash(:email, socket.assigns.user.email)
         |> push_navigate(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_layout flash={@flash}>
      <.header>
        Escolha uma senha nova
        <:subtitle>Ao salvar, todas as sessões abertas nesta conta são encerradas.</:subtitle>
      </.header>

      <.form for={@form} id="reset_form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input
          field={@form[:password]}
          type="password"
          label="Nova senha"
          autocomplete="new-password"
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Confirme a nova senha"
          autocomplete="new-password"
          required
        />
        <p class="text-xs text-base-content/60">Pelo menos 8 caracteres.</p>

        <div class="flex justify-end">
          <.button variant="primary" phx-disable-with="Salvando...">Salvar senha</.button>
        </div>
      </.form>

      <.auth_links show={[:login]} />
    </.auth_layout>
    """
  end
end
