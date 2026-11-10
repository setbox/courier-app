defmodule Courier.Core.Storage do
  @callback put(String.t(), binary(), String.t()) :: :ok | {:error, term()}
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}
  @callback delete(String.t()) :: :ok | {:error, term()}

  def bucket, do: config()[:bucket]

  def put(key, binary, content_type), do: impl().put(key, binary, content_type)

  def get(key), do: impl().get(key)

  def delete(key), do: impl().delete(key)

  def ensure_bucket! do
    case bucket() |> ExAws.S3.head_bucket() |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, _} ->
        bucket() |> ExAws.S3.put_bucket("us-east-1") |> ExAws.request!()
        :ok
    end
  end

  defp impl, do: config()[:impl] || __MODULE__.S3

  defp config, do: Application.fetch_env!(:courier, :storage)

  defmodule S3 do
    @behaviour Courier.Core.Storage

    alias Courier.Core.Storage

    @impl true
    def put(key, binary, content_type) do
      Storage.bucket()
      |> ExAws.S3.put_object(key, binary, content_type: content_type)
      |> ExAws.request()
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end

    @impl true
    def get(key) do
      Storage.bucket()
      |> ExAws.S3.get_object(key)
      |> ExAws.request()
      |> case do
        {:ok, %{body: body}} -> {:ok, body}
        {:error, reason} -> {:error, reason}
      end
    end

    @impl true
    def delete(key) do
      Storage.bucket()
      |> ExAws.S3.delete_object(key)
      |> ExAws.request()
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
