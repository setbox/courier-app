defmodule CourierWeb.McpLive do
  use CourierWeb, :live_view

  alias Courier.Core.Accounts
  alias CourierWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Acesso pelo MCP")
     |> assign(:mcp_url, Courier.MCP.Server.resource())
     |> load_tokens()}
  end

  @impl true
  def handle_event("revoke", %{"id" => id}, socket) do
    case Accounts.revoke_mcp_token(socket.assigns.current_scope.user, id) do
      :ok -> {:noreply, socket |> put_flash(:info, "Conexão revogada.") |> load_tokens()}
      _ -> {:noreply, socket |> put_flash(:error, "Conexão não encontrada.") |> load_tokens()}
    end
  end

  defp load_tokens(socket) do
    assign(socket, :tokens, Accounts.list_mcp_tokens(socket.assigns.current_scope.user))
  end

  defp when_used(nil), do: "nunca"
  defp when_used(datetime), do: Format.datetime(datetime)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Acesso pelo MCP
        <:subtitle>Assistentes de IA que consultam e operam o Courier em seu nome</:subtitle>
      </.header>

      <.card_section title="Endereço do conector">
        <:subtitle>
          No claude.ai, em Configurações, Conectores, adicione um conector personalizado com o endereço
          abaixo. O Claude abre a tela de autorização e a conexão aparece aqui.
        </:subtitle>
        <code id="mcp-url" class="block rounded-box bg-base-200 px-3 py-2 text-sm select-all">
          {@mcp_url}
        </code>
      </.card_section>

      <.empty_state :if={@tokens == []} title="Nenhuma conexão autorizada." />

      <.card :if={@tokens != []} id="mcp-tokens">
        <div
          :for={token <- @tokens}
          id={"mcp-token-#{token.id}"}
          class="flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-base-300 px-4 py-2.5 first:border-t-0"
        >
          <span class="flex min-w-0 flex-[1_1_260px] flex-col">
            <span class="truncate text-sm font-semibold">{token.name}</span>
            <span class="tabular text-xs text-neutral">
              Autorizada em {Format.datetime(token.inserted_at)} · último uso {when_used(
                token.last_used_at
              )}
            </span>
          </span>
          <.button
            id={"revoke-mcp-token-#{token.id}"}
            phx-click="revoke"
            phx-value-id={token.id}
            data-confirm={"Revogar a conexão #{token.name}? O assistente perde o acesso na hora."}
          >
            Revogar
          </.button>
        </div>
      </.card>
    </Layouts.app>
    """
  end
end
