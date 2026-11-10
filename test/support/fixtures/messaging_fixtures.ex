defmodule Courier.MessagingFixtures do
  alias Courier.Core.{Apps, Emails}

  def app_fixture(attrs \\ %{}) do
    {:ok, app} =
      attrs
      |> Enum.into(%{name: "App #{System.unique_integer([:positive])}"})
      |> Apps.create_app()

    app
  end

  def environment_fixture(attrs \\ %{}) do
    app = attrs[:app] || app_fixture()
    {:ok, environment} = Apps.create_environment(app, %{name: attrs[:name] || "prod"})
    %{environment | app: app}
  end

  def configured_environment_fixture(attrs \\ %{}) do
    environment = environment_fixture(attrs)

    {:ok, _config} =
      Apps.save_email_config(
        environment,
        %{
          "server_token" => "server-token-1234",
          "from_email" => "naoresponda@exemplo.com.br",
          "from_name" => "Exemplo",
          "message_stream" => "outbound"
        },
        "https://courier.test/webhooks/postmark/#{environment.id}"
      )

    {:ok, environment, token} = Apps.regenerate_client_token(environment)
    {environment, token}
  end

  def email_params(attrs \\ %{}) do
    Map.merge(
      %{
        "to" => ["ana@exemplo.com.br"],
        "subject" => "Bem-vinda",
        "html_body" => "<p>Olá</p>",
        "text_body" => "Olá"
      },
      attrs
    )
  end

  def email_fixture(environment, attrs \\ %{}) do
    {:ok, email, :created} = Emails.submit(environment, email_params(attrs))
    email
  end
end
