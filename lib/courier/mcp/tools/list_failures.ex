defmodule Courier.MCP.Tools.ListFailures do
  @moduledoc """
  Falhas de entrega no período: e-mails recusados pelo provider (failed), endereço não encontrado (not_found), outras devoluções (bounced) e marcação como spam (spam). Traz a contagem por tipo e a lista, da mais recente para a mais antiga. Só o que está dentro da retenção de 90 dias.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.{Emails, Stats}
  alias Courier.Core.Apps.ChannelConfig
  alias Courier.MCP
  alias Courier.MCP.Data

  @periods %{"7d" => :days_7, "30d" => :days_30, "12m" => :months_12}

  schema do
    field :period, :string, description: "7d, 30d (padrão) ou 12m"
    field :type, :string, description: "failed, not_found, bounced ou spam"
    field :environment_id, :string
    field :provider, :string, description: "postmark, brevo ou sandbox"
    field :recipient, :string, description: "Parte do e-mail ou domínio do destinatário"
    field :limit, :integer, description: "Até 200 (padrão 50)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn _user ->
      period = Map.get(@periods, MCP.arg(params, :period) || "30d", :days_30)
      type = Enum.find(Emails.failure_types(), &(Atom.to_string(&1) == MCP.arg(params, :type)))

      provider =
        Enum.find(ChannelConfig.providers(), &(Atom.to_string(&1) == MCP.arg(params, :provider)))

      filters = %{
        since: Stats.since(period),
        type: type,
        environment_id: MCP.arg(params, :environment_id),
        provider: provider,
        q: MCP.arg(params, :recipient)
      }

      MCP.reply(frame, %{
        contagem: Emails.count_failures(Map.delete(filters, :type)),
        falhas: filters |> Emails.list_failures(MCP.page(params)) |> Enum.map(&Data.failure/1)
      })
    end)
  end
end
