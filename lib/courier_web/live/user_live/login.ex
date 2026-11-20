defmodule CourierWeb.UserLive.Login do
  use CourierWeb, :live_view

  import CourierWeb.AuthLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Entrar")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.auth_layout flash={@flash}>
      <.header>
        Entrar
        <:subtitle>Com a conta Google. O acesso é criado pelo administrador.</:subtitle>
      </.header>

      <.google_button />
    </.auth_layout>
    """
  end
end
