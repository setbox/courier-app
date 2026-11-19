defmodule Courier.Core.Apps.ChannelConfig do
  use Ecto.Schema
  import Ecto.Changeset

  alias Courier.Core.Apps.Environment

  @channels [:email]
  @providers [:postmark, :mailtrap_sandbox]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "channel_configs" do
    field :channel, Ecto.Enum, values: @channels
    field :provider, Ecto.Enum, values: @providers
    field :server_token, Courier.Encrypted.Binary, redact: true
    field :server_token_hint, :string
    field :from_email, :string
    field :from_name, :string
    field :message_stream, :string, default: "outbound"
    field :track_opens, :boolean, default: false
    field :track_links, :boolean, default: false
    field :inbound_password, Courier.Encrypted.Binary, redact: true
    field :postmark_webhook_id, :integer
    field :postmark_webhook_error, :string
    field :mailtrap_inbox_id, :string

    belongs_to :environment, Environment

    timestamps(type: :utc_datetime)
  end

  def providers, do: @providers

  def provider_label(:postmark), do: "Postmark"
  def provider_label(:mailtrap_sandbox), do: "Mailtrap Sandbox"

  def email_changeset(config, attrs) do
    config
    |> cast(attrs, [
      :provider,
      :from_email,
      :from_name,
      :message_stream,
      :track_opens,
      :track_links,
      :mailtrap_inbox_id
    ])
    |> put_server_token(attrs)
    |> put_change(:channel, :email)
    |> put_default_provider()
    |> update_change(:from_email, &String.trim/1)
    |> update_change(:from_name, &String.trim/1)
    |> update_change(:mailtrap_inbox_id, &String.trim/1)
    |> validate_server_token()
    |> validate_required([:from_email], message: "não pode ficar em branco")
    |> validate_format(:from_email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "precisa ter o @ e não pode ter espaços"
    )
    |> validate_length(:from_name, max: 120, message: "deve ter no máximo 120 caracteres")
    |> validate_provider_fields()
    |> unique_constraint([:environment_id, :channel])
    |> ensure_inbound_password()
  end

  def ready?(%__MODULE__{provider: :mailtrap_sandbox, mailtrap_inbox_id: inbox} = config)
      when is_binary(inbox) and inbox != "",
      do: credentials_present?(config)

  def ready?(%__MODULE__{provider: :postmark} = config), do: credentials_present?(config)

  def ready?(_config), do: false

  defp credentials_present?(%__MODULE__{server_token: token, from_email: from}),
    do: is_binary(token) and token != "" and is_binary(from) and from != ""

  def new_inbound_password do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end

  defp put_server_token(changeset, attrs) do
    token = attrs["server_token"] || attrs[:server_token]

    case is_binary(token) && String.trim(token) do
      value when is_binary(value) and value != "" ->
        changeset
        |> put_change(:server_token, value)
        |> put_change(:server_token_hint, String.slice(value, -4, 4))

      _ ->
        changeset
    end
  end

  defp put_default_provider(changeset) do
    if get_field(changeset, :provider),
      do: changeset,
      else: put_change(changeset, :provider, :postmark)
  end

  defp validate_server_token(changeset) do
    provider = get_field(changeset, :provider)
    switched? = changed?(changeset, :provider) and not is_nil(changeset.data.provider)
    new_token? = changed?(changeset, :server_token)

    if switched? and not new_token? do
      add_error(changeset, :server_token, token_message(provider))
    else
      validate_required(changeset, [:server_token], message: token_message(provider))
    end
  end

  defp token_message(:mailtrap_sandbox), do: "informe o API Token do Mailtrap"
  defp token_message(_provider), do: "informe o Server API Token do Postmark"

  defp validate_provider_fields(changeset) do
    case get_field(changeset, :provider) do
      :mailtrap_sandbox ->
        changeset
        |> validate_required([:mailtrap_inbox_id], message: "informe o Inbox ID do Mailtrap")
        |> validate_format(:mailtrap_inbox_id, ~r/^\d+$/, message: "deve ter só números")

      _ ->
        validate_required(changeset, [:message_stream], message: "não pode ficar em branco")
    end
  end

  defp ensure_inbound_password(changeset) do
    if get_field(changeset, :inbound_password) do
      changeset
    else
      put_change(changeset, :inbound_password, new_inbound_password())
    end
  end
end
