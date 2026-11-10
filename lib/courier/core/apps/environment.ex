defmodule Courier.Core.Apps.Environment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Courier.Core.Apps.{App, ChannelConfig}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "environments" do
    field :name, :string
    field :slug, :string
    field :client_token_hash, :binary, redact: true
    field :client_token_hint, :string
    field :client_token_generated_at, :utc_datetime
    field :webhook_url, :string
    field :webhook_secret, Courier.Encrypted.Binary, redact: true
    field :allowed_recipients, {:array, :string}, default: []
    field :blocked_recipients, {:array, :string}, default: []

    belongs_to :app, App
    has_many :channel_configs, ChannelConfig

    timestamps(type: :utc_datetime)
  end

  def changeset(environment, attrs) do
    environment
    |> cast(attrs, [:name, :slug])
    |> update_change(:name, &String.trim/1)
    |> put_slug()
    |> validate_required([:name], message: "não pode ficar em branco")
    |> validate_length(:name, max: 60, message: "deve ter no máximo 60 caracteres")
    |> Courier.Core.Slug.validate(:slug)
    |> unique_constraint([:app_id, :slug], message: "já existe nesta aplicação")
  end

  def webhook_changeset(environment, attrs) do
    environment
    |> cast(attrs, [:webhook_url])
    |> update_change(:webhook_url, &blank_to_nil/1)
    |> validate_length(:webhook_url, max: 2000, message: "é longa demais")
    |> validate_change(:webhook_url, fn :webhook_url, url ->
      if valid_url?(url), do: [], else: [webhook_url: "precisa ser uma URL http ou https"]
    end)
  end

  def recipient_lists_changeset(environment, attrs) do
    environment
    |> cast(normalize_lists(attrs), [:allowed_recipients, :blocked_recipients])
    |> validate_entries(:allowed_recipients)
    |> validate_entries(:blocked_recipients)
  end

  def recipient_allowed?(%__MODULE__{} = environment, address) do
    address = String.downcase(String.trim(address))

    (environment.allowed_recipients == [] or matches?(environment.allowed_recipients, address)) and
      not matches?(environment.blocked_recipients, address)
  end

  defp matches?(entries, address) do
    domain = address |> String.split("@") |> List.last()
    Enum.any?(entries, &(&1 == address or &1 == "@" <> domain))
  end

  defp normalize_lists(attrs) do
    Map.new(attrs, fn
      {key, value}
      when key in ["allowed_recipients", "blocked_recipients"] and is_binary(value) ->
        {key, parse_entries(value)}

      {key, value} when key in ["allowed_recipients", "blocked_recipients"] and is_list(value) ->
        {key, value |> Enum.join("\n") |> parse_entries()}

      other ->
        other
    end)
  end

  defp parse_entries(text) do
    text
    |> String.split([",", ";", "\n", "\r", " ", "\t"], trim: true)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp validate_entries(changeset, field) do
    validate_change(changeset, field, fn ^field, entries ->
      case Enum.reject(entries, &valid_entry?/1) do
        [] -> []
        invalid -> [{field, "entradas inválidas: #{Enum.join(invalid, ", ")}"}]
      end
    end)
  end

  defp valid_entry?(entry) do
    Regex.match?(~r/^([^@,;<>\s]+)?@[^@,;<>\s]+\.[^@,;<>\s]+$/, entry)
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when slug in [nil, ""] ->
        put_change(changeset, :slug, Courier.Core.Slug.from(get_field(changeset, :name)))

      _slug ->
        changeset
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _ ->
        false
    end
  end
end
