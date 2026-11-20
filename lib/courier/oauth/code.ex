defmodule Courier.OAuth.Code do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "oauth_codes" do
    field :code_hash, :binary
    field :redirect_uri, :string
    field :code_challenge, :string
    field :expires_at, :utc_datetime

    belongs_to :client, Courier.OAuth.Client, type: :binary_id
    belongs_to :user, Courier.Core.Accounts.User, type: :binary_id

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
