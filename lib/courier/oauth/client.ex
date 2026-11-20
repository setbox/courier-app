defmodule Courier.OAuth.Client do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "oauth_clients" do
    field :name, :string
    field :redirect_uris, {:array, :string}
    field :token_endpoint_auth_method, :string
    field :secret_hash, :binary

    timestamps(type: :utc_datetime)
  end
end
