defmodule Courier.MCP.Tools.GenerateClientToken do
  @moduledoc """
  Gera o token de envio (cl_...) de um ambiente, que a aplicação manda no header Api-Key. O token anterior deixa de valer na hora. O valor aparece só nesta resposta: entregue à pessoa ou grave onde ela pediu, sem repetir depois. Pede confirmação à pessoa, com o motivo. Sem formulário, pergunte o motivo e se ela confirma, e chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => true}

  alias Courier.Core.Apps
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :environment_id, :string, required: true
    field :reason, :string, description: "Motivo dado pela pessoa (sem formulário)"
    field :confirm, :boolean, description: "true depois que a pessoa confirmou (sem formulário)"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn user ->
      case Apps.get_environment(MCP.arg(params, :environment_id)) do
        nil ->
          MCP.error(frame, "Ambiente não encontrado.")

        env ->
          action =
            if env.client_token_hint,
              do:
                "GERAR novo token de envio para #{Data.environment_label(env)}; o atual deixa de valer",
              else: "GERAR o token de envio de #{Data.environment_label(env)}"

          MCP.write(frame, user, params, %{
            tool: "generate_client_token",
            message: action,
            run: fn ->
              case Apps.regenerate_client_token(env) do
                {:ok, env, token} -> {:ok, %{token: token, final: env.client_token_hint}}
                {:error, changeset} -> {:error, changeset}
              end
            end
          })
      end
    end)
  end
end
