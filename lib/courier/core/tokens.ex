defmodule Courier.Core.Tokens do
  @client_prefix "cl_"

  def generate_client_token, do: generate(@client_prefix)

  def generate_secret(prefix \\ "whsec_"), do: generate(prefix)

  def hash(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  def hint(token) when is_binary(token), do: String.slice(token, -4, 4)

  def client_token?(token) when is_binary(token), do: String.starts_with?(token, @client_prefix)
  def client_token?(_token), do: false

  defp generate(prefix) do
    prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end
end
