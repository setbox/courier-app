defmodule Courier.Connectors.BrevoStub do
  def respond_with(fun) when is_function(fun, 1), do: Process.put(:brevo_stub, fun)

  def request(opts) do
    send(self(), {:brevo_request, opts})

    case Process.get(:brevo_stub) do
      nil -> default(opts)
      fun -> fun.(opts)
    end
  end

  defp default(opts) do
    case {opts[:method], opts[:url]} do
      {:post, "https://brevo.test/smtp/email"} ->
        {:ok,
         %{status: 201, body: %{"messageId" => "<#{Ecto.UUID.generate()}@smtp-relay.mailin.fr>"}}}

      {:post, "https://brevo.test/webhooks"} ->
        {:ok, %{status: 201, body: %{"id" => 77}}}

      {:put, "https://brevo.test/webhooks/" <> _id} ->
        {:ok, %{status: 204, body: ""}}
    end
  end
end
