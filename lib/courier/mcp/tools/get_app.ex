defmodule Courier.MCP.Tools.GetApp do
  @moduledoc """
  Uma aplicação e seus ambientes.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.Apps
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
    field :app_id, :string, required: true
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn _user ->
      MCP.reply(frame, params |> MCP.arg(:app_id) |> Apps.get_app!() |> Data.app())
    end)
  end
end
