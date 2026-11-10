defmodule CourierWeb.Plugs.ClientAuth do
  import Plug.Conn

  alias Courier.Core.Apps

  def init(opts), do: opts

  def call(conn, _opts) do
    with [token | _] <- get_req_header(conn, "api-key"),
         %{} = environment <- Apps.get_environment_by_client_token(String.trim(token)) do
      assign(conn, :environment, environment)
    else
      _ ->
        conn
        |> CourierWeb.Api.Error.send(401, "invalid_api_key", "Missing or invalid Api-Key header")
        |> halt()
    end
  end
end
