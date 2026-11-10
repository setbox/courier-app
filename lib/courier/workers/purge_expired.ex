defmodule Courier.Workers.PurgeExpired do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  alias Courier.Core.Emails

  @impl Oban.Worker
  def perform(_job) do
    Emails.purge_expired()
    :ok
  end
end
