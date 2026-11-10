defmodule Courier.Core.AppsTest do
  use Courier.DataCase, async: true

  import Courier.MessagingFixtures

  alias Courier.Connectors.PostmarkStub
  alias Courier.Core.Apps

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
end
