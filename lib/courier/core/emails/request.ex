defmodule Courier.Core.Emails.Request do
  use Ecto.Schema
  import Ecto.Changeset

  @address ~r/^[^@,;<>\s]+@[^@,;<>\s]+\.[^@,;<>\s]+$/
  @named_address ~r/^(?<name>[^<>]*)<(?<address>[^<>]+)>$/
  @max_recipients 50
  @max_metadata_keys 50
  @max_metadata_bytes 8_192

  @primary_key false
  embedded_schema do
    field :to, {:array, :string}, default: []
    field :cc, {:array, :string}, default: []
    field :bcc, {:array, :string}, default: []
    field :from, :string
    field :reply_to, :string
    field :subject, :string
    field :html_body, :string
    field :text_body, :string
    field :tag, :string
    field :message_stream, :string
    field :metadata, :map, default: %{}
    field :track_opens, :boolean
    field :track_links, :boolean
  end

  @fields [
    :to,
    :cc,
    :bcc,
    :from,
    :reply_to,
    :subject,
    :html_body,
    :text_body,
    :tag,
    :message_stream,
    :metadata,
    :track_opens,
    :track_links
  ]

  def changeset(params) when is_map(params) do
    %__MODULE__{}
    |> cast(wrap_addresses(params), @fields, empty_values: [])
    |> update_change(:to, &normalize_list/1)
    |> update_change(:cc, &normalize_list/1)
    |> update_change(:bcc, &normalize_list/1)
    |> validate_required([:subject], message: "can't be blank")
    |> validate_length(:subject, min: 1, max: 2000)
    |> validate_length(:to, min: 1, message: "must have at least one recipient")
    |> validate_addresses(:to)
    |> validate_addresses(:cc)
    |> validate_addresses(:bcc)
    |> validate_recipient_count()
    |> validate_body()
    |> validate_named_address(:from)
    |> validate_named_address(:reply_to)
    |> validate_length(:tag, max: 1000)
    |> validate_length(:message_stream, max: 100)
    |> validate_metadata()
  end

  def changeset(_params),
    do: change(%__MODULE__{}) |> add_error(:base, "body must be a JSON object")

  def address_of(value) when is_binary(value) do
    case Regex.named_captures(@named_address, String.trim(value)) do
      %{"address" => address} -> String.trim(address)
      nil -> String.trim(value)
    end
  end

  defp wrap_addresses(params) do
    Enum.reduce(["to", "cc", "bcc"], params, fn key, acc ->
      case Map.get(acc, key) do
        value when is_binary(value) -> Map.put(acc, key, [value])
        _ -> acc
      end
    end)
  end

  defp normalize_list(list), do: list |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp validate_addresses(changeset, field) do
    validate_change(changeset, field, fn ^field, list ->
      case Enum.reject(list, &Regex.match?(@address, &1)) do
        [] -> []
        invalid -> [{field, "invalid address: #{Enum.join(invalid, ", ")}"}]
      end
    end)
  end

  defp validate_recipient_count(changeset) do
    total =
      [:to, :cc, :bcc]
      |> Enum.map(&length(get_field(changeset, &1) || []))
      |> Enum.sum()

    if total > @max_recipients do
      add_error(changeset, :to, "at most #{@max_recipients} recipients across to, cc and bcc")
    else
      changeset
    end
  end

  defp validate_body(changeset) do
    html = get_field(changeset, :html_body)
    text = get_field(changeset, :text_body)

    if blank?(html) and blank?(text) do
      add_error(changeset, :html_body, "html_body or text_body is required")
    else
      changeset
    end
  end

  defp validate_named_address(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if Regex.match?(@address, address_of(value)),
        do: [],
        else: [{field, "invalid address"}]
    end)
  end

  defp validate_metadata(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      cond do
        map_size(metadata) > @max_metadata_keys ->
          [metadata: "at most #{@max_metadata_keys} keys"]

        not Enum.all?(metadata, fn {_key, value} -> scalar?(value) end) ->
          [metadata: "values must be strings, numbers, booleans or null"]

        byte_size(Jason.encode!(metadata)) > @max_metadata_bytes ->
          [metadata: "must be at most #{@max_metadata_bytes} bytes"]

        true ->
          []
      end
    end)
  end

  defp scalar?(value),
    do: is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
