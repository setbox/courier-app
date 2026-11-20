defmodule Courier.MCP.Tools.SendTestEmail do
  @moduledoc """
  Manda um e-mail de teste (transacional) por um ambiente, para conferir provider e remetente. Pede confirmação à pessoa, com o motivo. Se o aplicativo não mostrar formulário, pergunte o motivo e se ela confirma, e só então chame com `reason` e `confirm: true`.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"destructiveHint" => false}

  alias Courier.Core.{Apps, Emails}
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :environment_id, :string, required: true
    field :to, :string, required: true, description: "Destinatário do teste"
    field :subject, :string, description: "Padrão: Teste do Courier"
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
          to = MCP.arg(params, :to)
          subject = MCP.arg(params, :subject) || "Teste do Courier"

          MCP.write(frame, user, params, %{
            tool: "send_test_email",
            message:
              "ENVIAR e-mail de teste para #{to} pelo ambiente #{Data.environment_label(env)}",
            run: fn ->
              env
              |> Emails.submit(%{
                "category" => "transactional",
                "to" => [to],
                "subject" => subject,
                "text_body" => "Teste de envio pelo Courier, pedido por #{user.email}.",
                "html_body" => "<p>Teste de envio pelo Courier, pedido por #{user.email}.</p>",
                "tag" => "teste-courier"
              })
              |> case do
                {:ok, email, _outcome} -> {:ok, %{email_id: email.id, status: email.status}}
                {:error, reason} -> {:error, reason}
              end
            end
          })
      end
    end)
  end
end
