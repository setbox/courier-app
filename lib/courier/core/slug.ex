defmodule Courier.Core.Slug do
  import Ecto.Changeset

  def from(nil), do: nil

  def from(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  def validate(changeset, field) do
    changeset
    |> validate_required([field], message: "não pode ficar em branco")
    |> validate_length(field, max: 60, message: "deve ter no máximo 60 caracteres")
    |> validate_format(field, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "use letras minúsculas, números e hífen"
    )
  end
end
