defmodule Courier.MCP.Tools.ListUnsubscribes do
  @moduledoc """
  Endereços que cancelaram a inscrição de marketing num ambiente, do mais recente para o mais antigo.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.{Apps, Unsubscribes}
  alias Courier.MCP

  schema do
    field :environment_id, :string, required: true
    field :limit, :integer, description: "Até 200 (padrão 50)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn _user ->
      case Apps.get_environment(MCP.arg(params, :environment_id)) do
        nil ->
          MCP.error(frame, "Ambiente não encontrado.")

        env ->
          MCP.reply(frame, %{
            total: Unsubscribes.count(env),
            descadastros:
              env
              |> Unsubscribes.list(MCP.page(params))
              |> Enum.map(&%{endereco: &1.address, em: &1.inserted_at, email_id: &1.email_id})
          })
      end
    end)
  end
end
