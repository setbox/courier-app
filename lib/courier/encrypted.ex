defmodule Courier.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: Courier.Vault
end
