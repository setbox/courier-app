defmodule CourierWeb.AuditLive do
  use CourierWeb, :live_view

  alias Courier.Core.Audit
  alias CourierWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Auditoria")
     |> assign(:logs, Audit.list(%{}, 200))}
  end

  defp summary(%{"acao" => acao, "motivo" => motivo}), do: "#{acao}. Motivo: #{motivo}"
  defp summary(%{"conexao" => conexao}), do: conexao
  defp summary(_metadata), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Auditoria
        <:subtitle>
          Ações feitas pelo MCP e conexões autorizadas ou revogadas, das mais recentes
        </:subtitle>
      </.header>

      <.empty_state :if={@logs == []} title="Nada registrado ainda." />

      <.card :if={@logs != []} id="audit-logs">
        <div
          :for={log <- @logs}
          id={"audit-#{log.id}"}
          class="flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-base-300 px-4 py-2.5 first:border-t-0"
        >
          <span class="flex min-w-0 flex-[1_1_320px] flex-col">
            <span class="text-sm font-semibold">{Audit.action_label(log.action)}</span>
            <span class="truncate text-xs text-neutral">{summary(log.metadata)}</span>
          </span>
          <span class="text-xs text-neutral">{log.actor_email}</span>
          <span class="tabular text-xs whitespace-nowrap text-neutral">
            {Format.datetime(log.inserted_at)}
          </span>
        </div>
      </.card>
    </Layouts.app>
    """
  end
end
