defmodule Courier.Connectors.GoogleStub do
  @key :google_stub_userinfo

  def put_userinfo(body), do: Process.put(@key, body)

  def post(_url, _opts), do: {:ok, %{status: 200, body: %{"access_token" => "token-de-teste"}}}

  def get(_url, _opts) do
    case Process.get(@key) do
      nil -> {:ok, %{status: 401, body: %{}}}
      body -> {:ok, %{status: 200, body: body}}
    end
  end
end
