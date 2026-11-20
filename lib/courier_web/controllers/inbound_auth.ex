defmodule CourierWeb.InboundAuth do
  import Plug.Conn, only: [get_req_header: 2]

  alias Courier.Core.Apps

  def authenticate(conn, config) do
    with password when is_binary(password) <- config.inbound_password,
         {:ok, given} <- credential(conn),
         true <- Plug.Crypto.secure_compare(given, password) do
      :ok
    else
      _ -> :unauthorized
    end
  end

  defp credential(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> basic(conn)
    end
  end

  defp basic(conn) do
    case Plug.BasicAuth.parse_basic_auth(conn) do
      {username, password} -> if username == Apps.inbound_username(), do: {:ok, password}
      :error -> :error
    end
  end
end
