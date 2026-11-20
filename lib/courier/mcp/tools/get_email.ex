defmodule Courier.MCP.Tools.GetEmail do
  @moduledoc """
  Detalhe de um e-mail: destinatários com status, eventos, entregas do webhook para a aplicação e, se pedido, o corpo (HTML e texto).
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.{Emails, Webhooks}
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :email_id, :string, required: true
    field :include_body, :boolean, description: "true para trazer o corpo do e-mail"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn _user ->
      email = Emails.get_email!(MCP.arg(params, :email_id))
      data = Data.email(email, Emails.list_events(email), Webhooks.list_deliveries(email))

      data =
        if MCP.arg(params, :include_body) == true do
          case Emails.fetch_body(email) do
            {:ok, body} -> Map.put(data, :corpo, body)
            _ -> Map.put(data, :corpo, "indisponível no armazenamento")
          end
        else
          data
        end

      MCP.reply(frame, data)
    end)
  end
end
