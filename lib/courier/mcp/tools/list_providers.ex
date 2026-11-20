defmodule Courier.MCP.Tools.ListProviders do
  @moduledoc """
  Providers de e-mail do Courier (postmark, brevo, sandbox) e os ambientes que usam cada um.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.Apps
  alias Courier.Core.Apps.ChannelConfig
  alias Courier.MCP
  alias Courier.MCP.Data

  schema do
  end

  @impl true
  def execute(_params, frame) do
    MCP.with_user(frame, fn _user ->
      providers =
        Enum.map(ChannelConfig.providers(), fn provider ->
          %{
            provider: provider,
            nome: ChannelConfig.provider_label(provider),
            descricao: ChannelConfig.provider_description(provider),
            ambientes:
              Enum.map(
                Apps.list_environments_using(provider),
                &%{id: &1.id, nome: Data.environment_label(&1)}
              )
          }
        end)

      MCP.reply(frame, %{providers: providers})
    end)
  end
end
