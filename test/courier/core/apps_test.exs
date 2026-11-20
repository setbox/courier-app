defmodule Courier.Core.AppsTest do
  use Courier.DataCase, async: true

  import Courier.MessagingFixtures

  alias Courier.Connectors.{BrevoStub, PostmarkStub}
  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig

  describe "apps and environments" do
    test "derives the slug from the name" do
      {:ok, app} = Apps.create_app(%{name: "PJ Park"})
      assert app.slug == "pj-park"

      {:ok, environment} = Apps.create_environment(app, %{name: "Homologação"})
      assert environment.slug == "homologacao"
    end

    test "rejects a duplicated environment in the same app" do
      environment = environment_fixture(name: "prod")
      {:error, changeset} = Apps.create_environment(environment.app, %{name: "prod"})
      assert "já existe nesta aplicação" in errors_on(changeset).app_id
    end
  end

  describe "client token" do
    test "stores only the hash and finds the environment by the token" do
      environment = environment_fixture()
      {:ok, environment, token} = Apps.regenerate_client_token(environment)

      assert "cl_" <> _ = token
      assert environment.client_token_hint == String.slice(token, -4, 4)
      refute environment.client_token_hash == token
      assert Apps.get_environment_by_client_token(token).id == environment.id
    end

    test "regenerating invalidates the previous token" do
      environment = environment_fixture()
      {:ok, environment, old} = Apps.regenerate_client_token(environment)
      {:ok, _environment, new} = Apps.regenerate_client_token(environment)

      refute Apps.get_environment_by_client_token(old)
      assert Apps.get_environment_by_client_token(new)
    end

    test "ignores tokens without the prefix" do
      refute Apps.get_environment_by_client_token("whatever")
    end
  end

  describe "email config" do
    test "saves the config and registers the Postmark webhook" do
      environment = environment_fixture()

      {:ok, config} =
        Apps.save_email_config(
          environment,
          %{"server_token" => "abcd-1234", "from_email" => "a@exemplo.com.br"},
          "https://courier.test/hook"
        )

      assert config.server_token == "abcd-1234"
      assert config.server_token_hint == "1234"
      assert config.postmark_webhook_id == 1234
      assert is_binary(config.inbound_password)

      assert_received {:postmark_request, opts}
      assert opts[:json]["Url"] == "https://courier.test/hook"
      assert opts[:json]["HttpAuth"]["Password"] == config.inbound_password
    end

    test "keeps the server token when the field comes empty" do
      {environment, _token} = configured_environment_fixture()

      {:ok, config} =
        Apps.save_email_config(
          environment,
          %{"server_token" => "", "from_email" => "b@exemplo.com.br"},
          "https://courier.test/hook"
        )

      assert config.server_token == "server-token-1234"
      assert config.from_email == "b@exemplo.com.br"
    end

    test "records the Postmark error when the webhook registration fails" do
      environment = environment_fixture()

      PostmarkStub.respond_with(fn _opts ->
        {:ok, %{status: 401, body: %{"ErrorCode" => 10, "Message" => "Bad token"}}}
      end)

      {:ok, config} =
        Apps.save_email_config(
          environment,
          %{"server_token" => "x", "from_email" => "a@exemplo.com.br"},
          "https://courier.test/hook"
        )

      assert config.postmark_webhook_error == "Postmark 10: Bad token"
    end

    test "requires the server token on the first save" do
      environment = environment_fixture()

      {:error, changeset} =
        Apps.save_email_config(environment, %{"from_email" => "a@exemplo.com.br"}, "u")

      assert errors_on(changeset).server_token
    end

    test "saves a sandbox config without a token and without touching any provider" do
      environment = environment_fixture()

      {:ok, config} =
        Apps.save_email_config(
          environment,
          %{"provider" => "sandbox", "from_email" => "a@exemplo.com.br"},
          "u"
        )

      assert config.provider == :sandbox
      assert is_nil(config.server_token)
      assert ChannelConfig.ready?(config)
      refute_received {:postmark_request, _}
      refute_received {:brevo_request, _}
    end

    test "switching to the sandbox drops the provider token" do
      {environment, _token} = configured_environment_fixture()

      {:ok, config} = Apps.save_email_config(environment, %{"provider" => "sandbox"}, "u")

      assert config.provider == :sandbox
      assert is_nil(config.server_token)
      assert is_nil(config.server_token_hint)
      assert is_nil(config.postmark_webhook_id)
    end

    test "saves a Brevo config and registers the webhook with Basic Auth in the URL" do
      environment = environment_fixture()

      {:ok, config} =
        Apps.save_email_config(
          environment,
          %{
            "provider" => "brevo",
            "server_token" => "xkeysib-9876",
            "from_email" => "a@exemplo.com.br"
          },
          "https://courier.test/webhooks/brevo/#{environment.id}"
        )

      assert config.provider == :brevo
      assert config.brevo_webhook_id == 77
      assert is_nil(config.brevo_webhook_error)
      assert ChannelConfig.ready?(config)

      assert_received {:brevo_request, opts}
      assert opts[:method] == :post
      assert opts[:url] == "https://brevo.test/webhooks"
      assert {"api-key", "xkeysib-9876"} in opts[:headers]
      assert opts[:json]["type"] == "transactional"
      assert "delivered" in opts[:json]["events"]

      assert opts[:json]["url"] == "https://courier.test/webhooks/brevo/#{environment.id}"
      assert opts[:json]["auth"] == %{"type" => "bearer", "token" => config.inbound_password}

      refute_received {:postmark_request, _}
    end

    test "updates the existing Brevo webhook and creates it again when gone" do
      {environment, _token} = brevo_environment_fixture()
      config = Apps.email_config(environment)
      assert_received {:brevo_request, _create}

      config = Apps.register_webhook(config, "https://courier.test/hook")
      assert_received {:brevo_request, opts}
      assert opts[:method] == :put
      assert opts[:url] == "https://brevo.test/webhooks/77"
      assert config.brevo_webhook_id == 77

      BrevoStub.respond_with(fn opts ->
        case opts[:method] do
          :put -> {:ok, %{status: 404, body: %{"code" => "document_not_found"}}}
          :post -> {:ok, %{status: 201, body: %{"id" => 88}}}
        end
      end)

      assert Apps.register_webhook(config, "https://courier.test/hook").brevo_webhook_id == 88
    end

    test "keeps the Brevo error when the webhook is refused" do
      BrevoStub.respond_with(fn _ ->
        {:ok, %{status: 401, body: %{"code" => "unauthorized", "message" => "Key not found"}}}
      end)

      {:ok, config} =
        Apps.save_email_config(
          environment_fixture(),
          %{"provider" => "brevo", "server_token" => "bad", "from_email" => "a@exemplo.com.br"},
          "https://courier.test/hook"
        )

      assert config.brevo_webhook_error == "Brevo: unauthorized: Key not found"
      assert ChannelConfig.webhook_error(config) == config.brevo_webhook_error
    end

    test "switching from Postmark to Brevo clears the Postmark webhook" do
      {environment, _token} = configured_environment_fixture()
      assert Apps.email_config(environment).postmark_webhook_id

      {:ok, config} =
        Apps.save_email_config(
          environment,
          %{"provider" => "brevo", "server_token" => "xkeysib-1"},
          "https://courier.test/hook"
        )

      assert is_nil(config.postmark_webhook_id)
      assert config.brevo_webhook_id == 77
    end

    test "counts and lists the environments by provider" do
      {postmark, _token} = configured_environment_fixture()
      {brevo, _token} = brevo_environment_fixture()

      counts = Apps.count_environments_by_provider()
      assert counts[:postmark] >= 1
      assert counts[:brevo] >= 1

      ids = Enum.map(Apps.list_environments_using(:brevo), & &1.id)
      assert brevo.id in ids
      refute postmark.id in ids
    end

    test "switching the provider requires a new token" do
      {environment, _token} = configured_environment_fixture()

      {:error, changeset} =
        Apps.save_email_config(
          environment,
          %{"provider" => "brevo"},
          "u"
        )

      assert "informe a API Key do Brevo" in errors_on(changeset).server_token
    end
  end

  describe "recipient lists" do
    test "parses one entry per line, lowercases and removes duplicates" do
      environment = environment_fixture()

      {:ok, environment} =
        Apps.update_recipient_lists(environment, %{
          "allowed_recipients" => "@Setbox.com.br\nana@exemplo.com.br, ANA@exemplo.com.br",
          "blocked_recipients" => ""
        })

      assert environment.allowed_recipients == ["@setbox.com.br", "ana@exemplo.com.br"]
      assert environment.blocked_recipients == []
    end

    test "rejects invalid entries" do
      environment = environment_fixture()

      {:error, changeset} =
        Apps.update_recipient_lists(environment, %{"blocked_recipients" => "ana\n@x"})

      assert ["entradas inválidas: ana, @x"] = errors_on(changeset).blocked_recipients
    end

    test "whitelist restricts and blacklist blocks" do
      open = %Courier.Core.Apps.Environment{
        allowed_recipients: [],
        blocked_recipients: ["spam@exemplo.com.br"]
      }

      assert Courier.Core.Apps.Environment.recipient_allowed?(open, "ana@exemplo.com.br")
      refute Courier.Core.Apps.Environment.recipient_allowed?(open, "SPAM@exemplo.com.br")

      closed = %Courier.Core.Apps.Environment{
        allowed_recipients: ["@setbox.com.br", "ana@exemplo.com.br"],
        blocked_recipients: ["ex@setbox.com.br"]
      }

      assert Courier.Core.Apps.Environment.recipient_allowed?(closed, "jackson@setbox.com.br")
      assert Courier.Core.Apps.Environment.recipient_allowed?(closed, "ana@exemplo.com.br")
      refute Courier.Core.Apps.Environment.recipient_allowed?(closed, "bia@exemplo.com.br")
      refute Courier.Core.Apps.Environment.recipient_allowed?(closed, "x@sub.setbox.com.br")
      refute Courier.Core.Apps.Environment.recipient_allowed?(closed, "ex@setbox.com.br")
    end
  end

  describe "client webhook" do
    test "generates the secret once when the url is first set" do
      environment = environment_fixture()

      {:ok, environment, secret} =
        Apps.update_webhook(environment, %{"webhook_url" => "https://app.test/hook"})

      assert "whsec_" <> _ = secret

      {:ok, _environment, nil} =
        Apps.update_webhook(environment, %{"webhook_url" => "https://app.test/other"})
    end

    test "rejects invalid urls" do
      environment = environment_fixture()
      {:error, changeset} = Apps.update_webhook(environment, %{"webhook_url" => "ftp://x"})
      assert errors_on(changeset).webhook_url
    end
  end

  describe "webhook events" do
    alias Courier.Core.{Emails, Webhooks}

    test "only the chosen event types become deliveries" do
      {environment, _token} = Courier.MessagingFixtures.configured_environment_fixture()

      {:ok, environment, _secret} =
        Apps.update_webhook(environment, %{
          "webhook_url" => "https://app.test/hook",
          "webhook_events" => ["", "failed"]
        })

      assert environment.webhook_events == [:failed]

      email = Courier.MessagingFixtures.email_fixture(environment)
      {:ok, _} = Emails.mark_sent(email, "pm-x", :postmark)
      assert Webhooks.list_deliveries(email) == []

      other = Courier.MessagingFixtures.email_fixture(environment)
      {:ok, _} = Emails.mark_failed(other, 422, "recusado", :postmark)
      assert [_] = Webhooks.list_deliveries(other)
    end
  end
end
