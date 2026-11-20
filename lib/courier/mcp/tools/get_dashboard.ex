defmodule Courier.MCP.Tools.GetDashboard do
  @moduledoc """
  Painel do Courier: totais do período (enviados, entregues, com erro, não encontrado, devolvidos, spam) e a série por dia (7 ou 30 dias) ou por mês (12 meses), mais os enviados por provider. Dias no horário de Brasília.
  """

  use Anubis.Server.Component, type: :tool, annotations: %{"readOnlyHint" => true}

  alias Courier.Core.Stats
  alias Courier.MCP

  @periods %{"7d" => :days_7, "30d" => :days_30, "12m" => :months_12}

  schema do
    field :period, :string, description: "7d, 30d (padrão) ou 12m"
    field :environment_id, :string, description: "Só um ambiente"
    field :category, :string, description: "transactional ou marketing"
  end

  @impl true
  def execute(params, frame) do
    MCP.with_user(frame, fn _user ->
      with {:ok, period} <- period(MCP.arg(params, :period)),
           {:ok, category} <- category(MCP.arg(params, :category)) do
        series =
          Stats.series(period, %{
            environment_id: MCP.arg(params, :environment_id),
            category: category
          })

        MCP.reply(frame, %{
          totais: series.totals,
          agrupamento: series.bucket,
          serie: Enum.zip_with(series.buckets, series.points, &Map.put(&2, :inicio, &1)),
          enviados_por_provider: series.by_provider
        })
      else
        {:error, message} -> MCP.error(frame, message)
      end
    end)
  end

  defp period(value) when value in [nil, ""], do: {:ok, :days_30}

  defp period(value),
    do: Map.fetch(@periods, value) |> or_error("Período inválido: use 7d, 30d ou 12m.")

  defp category(value) when value in [nil, ""], do: {:ok, nil}
  defp category("transactional"), do: {:ok, :transactional}
  defp category("marketing"), do: {:ok, :marketing}
  defp category(_value), do: {:error, "Categoria inválida: use transactional ou marketing."}

  defp or_error({:ok, value}, _message), do: {:ok, value}
  defp or_error(:error, message), do: {:error, message}
end
