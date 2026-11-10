defmodule Courier.Core.Apps.App do
  use Ecto.Schema
  import Ecto.Changeset

  alias Courier.Core.Apps.Environment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "apps" do
    field :name, :string
    field :slug, :string

    has_many :environments, Environment, preload_order: [asc: :name]

    timestamps(type: :utc_datetime)
  end

  def changeset(app, attrs) do
    app
    |> cast(attrs, [:name, :slug])
    |> update_change(:name, &String.trim/1)
    |> put_slug()
    |> validate_required([:name], message: "não pode ficar em branco")
    |> validate_length(:name, max: 80, message: "deve ter no máximo 80 caracteres")
    |> Courier.Core.Slug.validate(:slug)
    |> unique_constraint(:slug, message: "já está em uso")
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when slug in [nil, ""] ->
        put_change(changeset, :slug, Courier.Core.Slug.from(get_field(changeset, :name)))

      _slug ->
        changeset
    end
  end
end
