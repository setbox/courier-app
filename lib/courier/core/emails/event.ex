defmodule Courier.Core.Emails.Event do
  use Ecto.Schema

  alias Courier.Core.Emails.{Email, Recipient}

  @types [
    :queued,
    :sent,
    :failed,
    :delivery,
    :bounce,
    :spam_complaint,
    :open,
    :click,
    :subscription_change
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "email_events" do
    field :type, Ecto.Enum, values: @types
    field :occurred_at, :utc_datetime
    field :data, :map, default: %{}

    belongs_to :email, Email
    belongs_to :recipient, Recipient

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def types, do: @types
end
