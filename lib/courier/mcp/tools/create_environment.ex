defmodule Courier.MCP.Tools.CreateEnvironment do
  @moduledoc """
  Cria um ambiente numa aplicação (local, dev, prod...). Depois, configure o e-mail com configure_email (Sandbox do Courier) ou pelo painel (Postmark e Brevo), e gere o token com generate_client_token. Pede confirmação à pessoa, com o motivo. Sem formulário, pergunte o motivo e se ela confirma, e chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => false}

  alias Courier.Core.Apps
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :app_id, :string, required: true
    field :name, :string, required: true
    field :reason, :string, description: "Motivo dado pela pessoa (sem formulário)"
    field :confirm, :boolean, description: "true depois que a pessoa confirmou (sem formulário)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn user ->
      app = Apps.get_app!(MCP.arg(params, :app_id))
      name = MCP.arg(params, :name)

      MCP.write(frame, user, params, %{
        tool: "create_environment",
        message: "CRIAR o ambiente #{name} na aplicação #{app.name}",
        run: fn ->
          app
          |> Apps.create_environment(%{name: name})
          |> MCP.ok(&%{ambiente: Data.environment_row(&1)})
        end
      })
    end)
  end
end
