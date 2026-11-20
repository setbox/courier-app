defmodule Courier.MCP.Tools.GetEnvironment do
  @moduledoc """
  Um ambiente: provider de e-mail, remetente, listas de permitidos e bloqueados, URL do webhook para a aplicação e quantos descadastros de marketing tem. Não traz token nem segredo.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.{Apps, Unsubscribes}
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :environment_id, :string, required: true
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn _user ->
      case Apps.get_environment(MCP.arg(params, :environment_id)) do
        nil ->
          MCP.error(frame, "Ambiente não encontrado.")

        env ->
          MCP.reply(frame, Data.environment(env, Apps.email_config(env), Unsubscribes.count(env)))
      end
    end)
  end
end
