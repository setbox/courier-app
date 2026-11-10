defmodule Courier.Connectors.PostmarkStub do
  def respond_with(fun) when is_function(fun, 1), do: Process.put(:postmark_stub, fun)

  def request(opts) do
    send(self(), {:postmark_request, opts})

    case Process.get(:postmark_stub) do
      nil -> default(opts)
      fun -> fun.(opts)
    end
  end

  defp default(opts) do
    case opts[:url] do
      "https://postmark.test/email" ->
        {:ok,
         %{
           status: 200,
           body: %{
             "MessageID" => Ecto.UUID.generate(),
             "SubmittedAt" => "2026-11-10T12:00:00Z",
             "ErrorCode" => 0
           }
         }}

      "https://postmark.test/webhooks" <> _ ->
        {:ok, %{status: 200, body: %{"ID" => 1234}}}
    end
  end
end
