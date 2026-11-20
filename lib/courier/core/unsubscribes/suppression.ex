defmodule Courier.Core.Unsubscribes.Suppression do
  use Ecto.Schema

  alias Courier.Core.Apps.Environment
  alias Courier.Core.Emails.Email

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "email_suppressions" do
    field :address, :string

    belongs_to :environment, Environment
    belongs_to :email, Email

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
