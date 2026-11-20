defmodule Courier.MCP.Tools.ListEmails do
  @moduledoc """
  E-mails recebidos pela API, do mais recente para o mais antigo, com filtros. Datas em AAAA-MM-DD.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.Emails
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :environment_id, :string
    field :app_id, :string
    field :status, :string, description: "queued, sent ou failed"
    field :category, :string, description: "transactional ou marketing"
    field :to, :string, description: "Endereço exato do destinatário"
    field :from_date, :string, description: "AAAA-MM-DD"
    field :to_date, :string, description: "AAAA-MM-DD"
    field :limit, :integer, description: "Até 100 (padrão 50)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn _user ->
      filters = [
        environment_id: MCP.arg(params, :environment_id),
        app_id: MCP.arg(params, :app_id),
        status: MCP.arg(params, :status),
        category: category(MCP.arg(params, :category)),
        to: MCP.arg(params, :to),
        from_date: MCP.arg(params, :from_date),
        to_date: MCP.arg(params, :to_date)
      ]

      {emails, _cursor} = Emails.list_emails(filters, limit: MCP.page(params, 50, 100))
      MCP.reply(frame, %{emails: Enum.map(emails, &Data.email_row/1)})
    end)
  end

  defp category("transactional"), do: :transactional
  defp category("marketing"), do: :marketing
  defp category(_value), do: nil
end
