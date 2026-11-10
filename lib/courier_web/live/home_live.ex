defmodule CourierWeb.HomeLive do
  use CourierWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Início")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Olá!
        <:subtitle>Você entrou como {@current_scope.user.email}.</:subtitle>
      </.header>
    </Layouts.app>
    """
  end
end
