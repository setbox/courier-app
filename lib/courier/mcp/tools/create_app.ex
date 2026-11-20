defmodule Courier.MCP.Tools.CreateApp do
  @moduledoc """
  Cria uma aplicação (sistema que envia pelo Courier). Pede confirmação à pessoa, com o motivo. Sem formulário, pergunte o motivo e se ela confirma, e chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => false}

  alias Courier.Core.Apps
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :name, :string, required: true
    field :reason, :string, description: "Motivo dado pela pessoa (sem formulário)"
    field :confirm, :boolean, description: "true depois que a pessoa confirmou (sem formulário)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn user ->
      name = MCP.arg(params, :name)

      MCP.write(frame, user, params, %{
        tool: "create_app",
        message: "CRIAR a aplicação #{name}",
        run: fn -> %{name: name} |> Apps.create_app() |> MCP.ok(&%{aplicacao: Data.app(&1)}) end
      })
    end)
  end
end
