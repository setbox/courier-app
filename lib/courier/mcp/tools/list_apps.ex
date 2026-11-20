defmodule Courier.MCP.Tools.ListApps do
  @moduledoc """
  Aplicações cadastradas no Courier, com os ambientes de cada uma.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.Apps
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
  end

  @impl true
  def execute(_params, frame) do
    MCP.with_user(frame, fn _user ->
      MCP.reply(frame, %{aplicacoes: Enum.map(Apps.list_apps(), &Data.app/1)})
    end)
  end
end
