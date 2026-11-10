defmodule Courier.Workers.DeliverWebhook do
  use Oban.Worker, queue: :webhooks, max_attempts: 14

  alias Courier.Core.Webhooks
  alias Courier.Core.Webhooks.Delivery
  alias Courier.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => id}, attempt: attempt, max_attempts: max}) do
    case Repo.get(Delivery, id) do
      %Delivery{status: :pending} ->
        id
        |> Webhooks.get_delivery!()
        |> Webhooks.deliver(attempt >= max)

      _ ->
        :ok
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    trunc(min(:math.pow(2, attempt) * 10, 4 * 60 * 60))
  end
end
