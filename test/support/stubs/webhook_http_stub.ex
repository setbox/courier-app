defmodule Courier.Webhooks.HttpStub do
  def respond_with(response), do: Process.put(:webhook_http_stub, response)

  def post(url, opts) do
    send(self(), {:webhook_post, url, opts})
    Process.get(:webhook_http_stub, {:ok, %{status: 200}})
  end
end
