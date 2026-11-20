defmodule Courier.Workers.RebuildStats do
  use Oban.Worker, queue: :maintenance, max_attempts: 3, unique: [period: 300]

  alias Courier.Core.Stats

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _count} = Stats.rebuild()
    :ok
  end
end
