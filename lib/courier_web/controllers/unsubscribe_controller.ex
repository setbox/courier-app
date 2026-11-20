defmodule CourierWeb.UnsubscribeController do
  use CourierWeb, :controller

  alias Courier.Core.Unsubscribes

  plug :put_layout, false
  plug :put_root_layout, false

  def show(conn, %{"token" => token}) do
    case Unsubscribes.verify(token) do
      {:ok, %{address: address}} -> render(conn, :show, address: address, token: token)
      :error -> conn |> put_status(:not_found) |> render(:invalid)
    end
  end

  def create(conn, %{"token" => token}) do
    case Unsubscribes.unsubscribe(token) do
      {:ok, address} -> render(conn, :done, address: address)
      :error -> conn |> put_status(:not_found) |> render(:invalid)
    end
  end
end
