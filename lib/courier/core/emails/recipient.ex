defmodule Courier.Core.Emails.Recipient do
  use Ecto.Schema

  alias Courier.Core.Emails.Email

  @kinds [:to, :cc, :bcc]
  @statuses [:pending, :delivered, :bounced, :spam_complaint]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "email_recipients" do
    field :kind, Ecto.Enum, values: @kinds
    field :address, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :status_at, :utc_datetime
    field :detail, :string
    field :opened_at, :utc_datetime
    field :clicked_at, :utc_datetime

    belongs_to :email, Email
  end
end
