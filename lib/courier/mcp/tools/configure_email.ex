defmodule Courier.MCP.Tools.ConfigureEmail do
  @moduledoc """
  Configura o e-mail de um ambiente no Sandbox do Courier: o Courier guarda o e-mail e não envia a ninguém (para local, dev, stage). Só o Sandbox, que não tem segredo; Postmark e Brevo, que têm chave, ficam no painel. Pede confirmação à pessoa, com o motivo. Sem formulário, pergunte o motivo e se ela confirma, e chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => true}

  alias Courier.Core.Apps
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :environment_id, :string, required: true
    field :from_email, :string, required: true, description: "E-mail do remetente padrão"
    field :from_name, :string, description: "Nome do remetente padrão"
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
          from_email = MCP.arg(params, :from_email)

          MCP.write(frame, user, params, %{
            tool: "configure_email",
            message:
              "CONFIGURAR #{Data.environment_label(env)} no Sandbox do Courier, remetente #{from_email}",
            run: fn ->
              env
              |> Apps.save_email_config(
                %{
                  "provider" => "sandbox",
                  "from_email" => from_email,
                  "from_name" => MCP.arg(params, :from_name)
                },
                ""
              )
              |> MCP.ok(
                &%{
                  provider: &1.provider,
                  remetente: &1.from_email,
                  nome_do_remetente: &1.from_name
                }
              )
            end
          })
      end
    end)
  end
end
