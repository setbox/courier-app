defmodule Courier.Connectors.MailtrapStub do
  def respond_with(fun) when is_function(fun, 1), do: Process.put(:mailtrap_stub, fun)

  def request(opts) do
    send(self(), {:mailtrap_request, opts})

    case Process.get(:mailtrap_stub) do
      nil -> {:ok, %{status: 200, body: %{"success" => true, "message_ids" => ["mt-1"]}}}
      fun -> fun.(opts)
    end
  end
end
