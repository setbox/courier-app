defmodule Courier.Core.Webhooks.Delivery do
  use Ecto.Schema

  alias Courier.Core.Emails.Event

  @statuses [:pending, :delivered, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webhook_deliveries" do
    field :url, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :attempts, :integer, default: 0
    field :response_status, :integer
    field :response_error, :string
    field :last_attempt_at, :utc_datetime
    field :delivered_at, :utc_datetime

    belongs_to :email_event, Event

    timestamps(type: :utc_datetime)
  end
end
