defmodule Courier.Core.StorageStub do
  @behaviour Courier.Core.Storage

  @table :courier_storage_stub

  @impl true
  def put(key, binary, _content_type) do
    if Process.get(:storage_unavailable) do
      {:error, :unavailable}
    else
      :ets.insert(table(), {key, binary})
      :ok
    end
  end

  @impl true
  def get(key) do
    case :ets.lookup(table(), key) do
      [{^key, binary}] -> {:ok, binary}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def delete(key) do
    :ets.delete(table(), key)
    :ok
  end

  def fail_next_puts, do: Process.put(:storage_unavailable, true)

  def start, do: :ets.new(@table, [:named_table, :public, :set])

  defp table, do: @table
end
