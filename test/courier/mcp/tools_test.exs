defmodule Courier.MCP.ToolsTest do
  use Courier.DataCase, async: true

  import Courier.Core.AccountsFixtures
  import Courier.MessagingFixtures
  import Courier.MCPHelpers

  alias Courier.Core.{Emails, Unsubscribes}
  alias Courier.Core.Audit.AuditLog
  alias Courier.MCP.Tools

  import Ecto.Query

  setup do
    user = user_fixture()
    {environment, _token} = configured_environment_fixture()
    email = email_fixture(environment)
    {:ok, _} = Emails.mark_failed(email, 406, "Inactive recipient", :postmark)
    %{user: user, frame: frame(user), environment: environment, email: email}
  end

  test "every read tool answers", %{frame: frame, environment: environment, email: email} do
    assert {:ok, %{"totais" => %{"failed" => 1}}} =
             call(Tools.GetDashboard, %{period: "7d"}, frame)

    assert {:ok, %{"contagem" => %{"failed" => 1}}} = call(Tools.ListFailures, %{}, frame)

    assert {:ok, %{"emails" => [%{"id" => id}]}} =
             call(Tools.ListEmails, %{environment_id: environment.id}, frame)

    assert id == email.id
    assert {:ok, %{"eventos" => [_ | _]}} = call(Tools.GetEmail, %{email_id: email.id}, frame)
    assert {:ok, %{"aplicacoes" => [_ | _]}} = call(Tools.ListApps, %{}, frame)
    assert {:ok, %{"ambientes" => [_]}} = call(Tools.GetApp, %{app_id: environment.app_id}, frame)

    assert {:ok, env} = call(Tools.GetEnvironment, %{environment_id: environment.id}, frame)
    assert env["email"]["provider"] == "postmark"
    refute inspect(env) =~ "server-token"

    assert {:ok, %{"providers" => [_, _, _]}} = call(Tools.ListProviders, %{}, frame)

    assert {:ok, %{"total" => 0}} =
             call(Tools.ListUnsubscribes, %{environment_id: environment.id}, frame)

    assert {:ok, %{"registros" => []}} = call(Tools.SearchAudit, %{}, frame)
  end

  test "an action asks for reason and confirmation before changing anything", %{frame: frame} do
    assert {:error, message} = call(Tools.CreateApp, %{name: "Planta"}, frame)
    assert message =~ "motivo"

    assert {:error, message} =
             call(Tools.CreateApp, %{name: "Planta", reason: "novo produto"}, frame)

    assert message =~ "confirm: true"

    assert {:ok, %{"status" => "ok", "aplicacao" => %{"nome" => "Planta"}}} =
             call(
               Tools.CreateApp,
               %{name: "Planta", reason: "novo produto", confirm: true},
               frame
             )

    log = Repo.get_by!(AuditLog, action: "mcp_write")
    assert log.metadata["ferramenta"] == "create_app"
    assert log.metadata["motivo"] == "novo produto"
  end

  test "with an elicitation form, accepting runs the action and declining does not", %{user: user} do
    elicit = frame(user, era: :stateless, elicitation: true)
    assert {:input_required, _} = call(Tools.CreateApp, %{name: "Jayio"}, elicit)

    declined = frame(user, era: :stateless, elicitation: true, responses: decline())
    assert {:ok, %{"status" => "cancelado"}} = call(Tools.CreateApp, %{name: "Jayio"}, declined)

    accepted =
      frame(user, era: :stateless, elicitation: true, responses: accept(%{"motivo" => "teste"}))

    assert {:ok, %{"status" => "ok"}} = call(Tools.CreateApp, %{name: "Jayio"}, accepted)
  end

  test "write tools change what they say", %{frame: frame, environment: environment, email: email} do
    confirm = &Map.merge(&1, %{reason: "teste", confirm: true})

    assert {:ok, %{"ambiente" => %{"nome" => "stage"}}} =
             call(
               Tools.CreateEnvironment,
               confirm.(%{app_id: environment.app_id, name: "stage"}),
               frame
             )

    assert {:ok, %{"permitidos" => ["@setbox.com.br"]}} =
             call(
               Tools.UpdateRecipientLists,
               confirm.(%{environment_id: environment.id, allowed: ["@setbox.com.br"]}),
               frame
             )

    assert {:ok, %{"email_id" => _}} =
             call(
               Tools.SendTestEmail,
               confirm.(%{environment_id: environment.id, to: "ana@setbox.com.br"}),
               frame
             )

    marketing =
      email_fixture(environment, %{"category" => "marketing", "to" => ["bia@setbox.com.br"]})

    token =
      marketing |> Unsubscribes.url("bia@setbox.com.br") |> String.split("/u/") |> List.last()

    {:ok, _} = Unsubscribes.unsubscribe(token)

    assert {:ok, %{"reinscrito" => "bia@setbox.com.br"}} =
             call(
               Tools.RemoveUnsubscribe,
               confirm.(%{environment_id: environment.id, address: "bia@setbox.com.br"}),
               frame
             )

    assert {:error, "Registro não encontrado."} =
             call(Tools.RedeliverWebhook, confirm.(%{delivery_id: Ecto.UUID.generate()}), frame)

    assert email.id
  end

  test "configures the sandbox and generates a working token", %{frame: frame, user: user} do
    {:ok, app} = Courier.Core.Apps.create_app(%{name: "PJPark"})
    {:ok, env} = Courier.Core.Apps.create_environment(app, %{name: "local"})
    confirm = &Map.merge(&1, %{reason: "dev do pjpark", confirm: true})

    assert {:ok, %{"provider" => "sandbox", "remetente" => "naoresponda@pjpark.com.br"}} =
             call(
               Tools.ConfigureEmail,
               confirm.(%{
                 environment_id: env.id,
                 from_email: "naoresponda@pjpark.com.br",
                 from_name: "PJ Park"
               }),
               frame
             )

    assert {:ok, %{"token" => "cl_" <> _ = token}} =
             call(Tools.GenerateClientToken, confirm.(%{environment_id: env.id}), frame)

    assert Courier.Core.Apps.get_environment_by_client_token(token).id == env.id

    logs = Repo.all(from a in AuditLog, where: a.action == "mcp_write")
    refute Enum.any?(logs, &(inspect(&1.metadata) =~ token))
    assert user.id
  end

  test "configures the webhook with chosen events and returns the secret once", %{
    frame: frame,
    environment: environment
  } do
    confirm = &Map.merge(&1, %{reason: "receber eventos", confirm: true})

    params = %{
      environment_id: environment.id,
      url: "https://app.test/hook",
      events: ["failed", "not_found"]
    }

    assert {:ok, %{"segredo" => "whsec_" <> _, "eventos" => ["failed", "not_found"]}} =
             call(Tools.ConfigureWebhook, confirm.(params), frame)

    assert {:ok, again} =
             call(Tools.ConfigureWebhook, confirm.(%{params | events: ["sent"]}), frame)

    refute Map.has_key?(again, "segredo")

    assert {:error, message} =
             call(Tools.ConfigureWebhook, confirm.(%{params | events: ["opened"]}), frame)

    assert message =~ "Evento inválido"
  end
end
