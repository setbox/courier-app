defmodule Courier.Core.Audit.AuditLog do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_logs" do
    field :action, :string
    field :actor_email, :string
    field :metadata, :map, default: %{}

    belongs_to :actor, Courier.Core.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
