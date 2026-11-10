defmodule Courier.Core.Emails.Email do
  use Ecto.Schema

  alias Courier.Core.Apps.Environment
  alias Courier.Core.Emails.{Event, Recipient}

  @statuses [:queued, :sent, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "emails" do
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :from, :string
    field :subject, :string
    field :reply_to, :string
    field :tag, :string
    field :message_stream, :string
    field :metadata, :map, default: %{}
    field :idempotency_key, :string
    field :track_opens, :boolean, default: false
    field :track_links, :boolean, default: false
    field :body_key, :string
    field :provider_message_id, :string
    field :error_code, :integer
    field :error_message, :string
    field :attempts, :integer, default: 0
    field :sent_at, :utc_datetime
    field :failed_at, :utc_datetime

    belongs_to :environment, Environment
    has_many :recipients, Recipient, preload_order: [asc: :kind, asc: :address]
    has_many :events, Event, preload_order: [asc: :occurred_at, asc: :inserted_at]

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses
end
