defmodule CourierWeb.InboundAuth do
  alias Courier.Core.Apps

  def authenticate(conn, config) do
    with password when is_binary(password) <- config.inbound_password,
         {username, given} <- Plug.BasicAuth.parse_basic_auth(conn),
         true <- username == Apps.inbound_username(),
         true <- Plug.Crypto.secure_compare(given, password) do
      :ok
    else
      _ -> :unauthorized
    end
  end
end
