defmodule CourierWeb.UserSessionController do
  use CourierWeb, :controller

  alias CourierWeb.UserAuth

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Sessão encerrada.")
    |> UserAuth.log_out_user()
  end
end
