defmodule Courier.Core.Accounts.Scope do
  alias Courier.Core.Accounts.User

  defstruct user: nil

  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil
end
