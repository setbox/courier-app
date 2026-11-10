defmodule Courier.Core.Apps.ChannelConfig do
  use Ecto.Schema
  import Ecto.Changeset

  alias Courier.Core.Apps.Environment

  @channels [:email]
  @providers [:postmark]

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

    belongs_to :environment, Environment

    timestamps(type: :utc_datetime)
  end

  def email_changeset(config, attrs) do
    config
    |> cast(attrs, [:from_email, :from_name, :message_stream, :track_opens, :track_links])
    |> put_server_token(attrs)
    |> put_change(:channel, :email)
    |> put_change(:provider, :postmark)
    |> update_change(:from_email, &String.trim/1)
    |> update_change(:from_name, &String.trim/1)
    |> validate_required([:server_token],
      message: "informe o Server API Token do Postmark"
    )
    |> validate_required([:from_email, :message_stream], message: "não pode ficar em branco")
    |> validate_format(:from_email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "precisa ter o @ e não pode ter espaços"
    )
    |> validate_length(:from_name, max: 120, message: "deve ter no máximo 120 caracteres")
    |> unique_constraint([:environment_id, :channel])
    |> ensure_inbound_password()
  end

  def ready?(%__MODULE__{server_token: token, from_email: from})
      when is_binary(token) and token != "" and is_binary(from) and from != "",
      do: true

  def ready?(_config), do: false

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

  defp ensure_inbound_password(changeset) do
    if get_field(changeset, :inbound_password) do
      changeset
    else
      put_change(changeset, :inbound_password, new_inbound_password())
    end
  end
end
