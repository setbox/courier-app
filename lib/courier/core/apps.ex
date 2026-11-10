defmodule Courier.Core.Apps do
  import Ecto.Query, warn: false

  alias Courier.Connectors.Postmark
  alias Courier.Core.Apps.{App, ChannelConfig, Environment}
  alias Courier.Core.Tokens
  alias Courier.Repo

  def list_apps do
    Repo.all(
      from a in App,
        order_by: [asc: a.name],
        preload: [environments: ^from(e in Environment, order_by: [asc: e.name])]
    )
  end

  def list_environments do
    Repo.all(
      from e in Environment,
        join: a in assoc(e, :app),
        order_by: [asc: a.name, asc: e.name],
        preload: [app: a]
    )
  end

  def get_app!(id) do
    App
    |> Repo.get!(id)
    |> Repo.preload(environments: from(e in Environment, order_by: [asc: e.name]))
  end

  def change_app(%App{} = app, attrs \\ %{}), do: App.changeset(app, attrs)

  def create_app(attrs) do
    %App{}
    |> App.changeset(attrs)
    |> Repo.insert()
  end

  def update_app(%App{} = app, attrs) do
    app
    |> App.changeset(attrs)
    |> Repo.update()
  end

  def get_environment!(app_id, id) do
    Environment
    |> where(app_id: ^app_id)
    |> Repo.get!(id)
    |> Repo.preload(:app)
  end

  def get_environment(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Environment |> Repo.get(uuid) |> Repo.preload(:app)
      :error -> nil
    end
  end

  def change_environment(%Environment{} = environment, attrs \\ %{}),
    do: Environment.changeset(environment, attrs)

  def create_environment(%App{} = app, attrs) do
    %Environment{app_id: app.id}
    |> Environment.changeset(attrs)
    |> Repo.insert()
  end

  def update_environment(%Environment{} = environment, attrs) do
    environment
    |> Environment.changeset(attrs)
    |> Repo.update()
  end

  def regenerate_client_token(%Environment{} = environment) do
    token = Tokens.generate_client_token()

    environment
    |> Ecto.Changeset.change(
      client_token_hash: Tokens.hash(token),
      client_token_hint: Tokens.hint(token),
      client_token_generated_at: DateTime.utc_now(:second)
    )
    |> Repo.update()
    |> case do
      {:ok, environment} -> {:ok, environment, token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def get_environment_by_client_token(token) do
    if Tokens.client_token?(token) do
      Environment
      |> Repo.get_by(client_token_hash: Tokens.hash(token))
      |> Repo.preload(:app)
    end
  end

  def change_webhook(%Environment{} = environment, attrs \\ %{}),
    do: Environment.webhook_changeset(environment, attrs)

  def update_webhook(%Environment{} = environment, attrs) do
    changeset = Environment.webhook_changeset(environment, attrs)

    {changeset, secret} =
      if Ecto.Changeset.get_field(changeset, :webhook_url) && is_nil(environment.webhook_secret) do
        secret = Tokens.generate_secret()
        {Ecto.Changeset.put_change(changeset, :webhook_secret, secret), secret}
      else
        {changeset, nil}
      end

    case Repo.update(changeset) do
      {:ok, environment} -> {:ok, environment, secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def change_recipient_lists(%Environment{} = environment, attrs \\ %{}),
    do: Environment.recipient_lists_changeset(environment, attrs)

  def update_recipient_lists(%Environment{} = environment, attrs) do
    environment
    |> Environment.recipient_lists_changeset(attrs)
    |> Repo.update()
  end

  def regenerate_webhook_secret(%Environment{} = environment) do
    secret = Tokens.generate_secret()

    environment
    |> Ecto.Changeset.change(webhook_secret: secret)
    |> Repo.update()
    |> case do
      {:ok, environment} -> {:ok, environment, secret}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def email_config(%Environment{id: environment_id}) do
    Repo.get_by(ChannelConfig, environment_id: environment_id, channel: :email)
  end

  def change_email_config(%ChannelConfig{} = config, attrs \\ %{}),
    do: ChannelConfig.email_changeset(config, attrs)

  def save_email_config(%Environment{} = environment, attrs, inbound_url) do
    config = email_config(environment) || %ChannelConfig{environment_id: environment.id}

    with {:ok, config} <-
           config |> ChannelConfig.email_changeset(attrs) |> Repo.insert_or_update() do
      {:ok, register_postmark_webhook(config, inbound_url)}
    end
  end

  def regenerate_inbound_password(%ChannelConfig{} = config, inbound_url) do
    config
    |> Ecto.Changeset.change(inbound_password: ChannelConfig.new_inbound_password())
    |> Repo.update!()
    |> register_postmark_webhook(inbound_url)
  end

  def inbound_username, do: "courier"

  def register_postmark_webhook(%ChannelConfig{} = config, inbound_url) do
    result =
      Postmark.upsert_webhook(config.server_token, config.postmark_webhook_id, %{
        url: inbound_url,
        username: inbound_username(),
        password: config.inbound_password,
        message_stream: config.message_stream
      })

    changes =
      case result do
        {:ok, webhook_id} -> [postmark_webhook_id: webhook_id, postmark_webhook_error: nil]
        {:error, reason} -> [postmark_webhook_error: Postmark.describe_error(reason)]
      end

    config
    |> Ecto.Changeset.change(changes)
    |> Repo.update!()
  end
end
