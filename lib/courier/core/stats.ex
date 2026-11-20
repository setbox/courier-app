defmodule Courier.Core.Stats do
  import Ecto.Query, warn: false

  alias Courier.Core.Emails.{Email, Recipient}
  alias Courier.Core.Stats.DailyStat
  alias Courier.Repo

  @utc_offset_hours -3
  @rebuild_days 7
  @first_rebuild_days 90
  @metrics DailyStat.metrics()

  defmacrop local_day(column) do
    quote do
      fragment("(? AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date", unquote(column))
    end
  end

  def today,
    do: DateTime.utc_now() |> DateTime.add(@utc_offset_hours, :hour) |> DateTime.to_date()

  def rebuild do
    days = if Repo.exists?(DailyStat), do: @rebuild_days, else: @first_rebuild_days
    yesterday = Date.add(today(), -1)
    rebuild(Date.add(yesterday, -(days - 1)), yesterday)
  end

  def rebuild(%Date{} = from, %Date{} = to) do
    now = DateTime.utc_now(:second)

    rows =
      from
      |> aggregate(to)
      |> Enum.map(&Map.merge(&1, %{id: Ecto.UUID.generate(), inserted_at: now, updated_at: now}))

    Repo.transact(fn ->
      Repo.delete_all(from s in DailyStat, where: s.day >= ^from and s.day <= ^to)
      rows |> Enum.chunk_every(1000) |> Enum.each(&Repo.insert_all(DailyStat, &1))
      {:ok, length(rows)}
    end)
  end

  def aggregate(%Date{} = from, %Date{} = to) do
    {start_at, end_at} = utc_range(from, to)

    [
      email_counts(:sent, :sent_at, start_at, end_at),
      email_counts(:failed, :failed_at, start_at, end_at),
      recipient_counts(start_at, end_at)
    ]
    |> Enum.concat()
    |> Enum.reduce(%{}, fn {key, metric, count}, acc ->
      Map.update(
        acc,
        key,
        %{metric => count},
        &Map.update(&1, metric, count, fn n -> n + count end)
      )
    end)
    |> Enum.map(fn {{day, environment_id, provider, category}, counts} ->
      Map.merge(
        %{day: day, environment_id: environment_id, provider: provider, category: category},
        Map.new(@metrics, &{&1, Map.get(counts, &1, 0)})
      )
    end)
  end

  def series(period, filters \\ %{}) do
    {from, to, bucket} = range(period)
    today = today()

    stored =
      Repo.all(
        from s in filtered(DailyStat, filters),
          where: s.day >= ^from and s.day <= ^to and s.day < ^today
      )

    live =
      if Date.compare(to, today) != :lt, do: today |> aggregate(today) |> keep(filters), else: []

    rows = Enum.map(stored, &Map.from_struct/1) ++ live
    buckets = buckets(from, to, bucket)

    %{
      buckets: buckets,
      bucket: bucket,
      totals: totals(rows),
      points:
        Enum.map(buckets, fn b -> totals(Enum.filter(rows, &(bucket_of(&1.day, bucket) == b))) end),
      by_provider: by_provider(rows, buckets, bucket)
    }
  end

  def since(period) do
    {from, _to, _bucket} = range(period)
    local_midnight(from)
  end

  defp range(:days_7), do: {Date.add(today(), -6), today(), :day}
  defp range(:days_30), do: {Date.add(today(), -29), today(), :day}

  defp range(:months_12) do
    to = today()
    from = to |> Date.beginning_of_month() |> Date.shift(month: -11)
    {from, to, :month}
  end

  defp buckets(from, to, :day), do: Date.range(from, to) |> Enum.to_list()

  defp buckets(from, _to, :month), do: Enum.map(0..11, &Date.shift(from, month: &1))

  defp bucket_of(day, :day), do: day
  defp bucket_of(day, :month), do: Date.beginning_of_month(day)

  defp totals(rows), do: Map.new(@metrics, fn m -> {m, Enum.sum_by(rows, &Map.get(&1, m, 0))} end)

  defp by_provider(rows, buckets, bucket) do
    rows
    |> Enum.group_by(& &1.provider)
    |> Map.new(fn {provider, provider_rows} ->
      {provider,
       Enum.map(buckets, fn b ->
         provider_rows |> Enum.filter(&(bucket_of(&1.day, bucket) == b)) |> Enum.sum_by(& &1.sent)
       end)}
    end)
  end

  defp filtered(query, filters) do
    Enum.reduce(filters, query, fn
      {:environment_id, id}, q when is_binary(id) -> where(q, [s], s.environment_id == ^id)
      {:category, c}, q when is_atom(c) and not is_nil(c) -> where(q, [s], s.category == ^c)
      _, q -> q
    end)
  end

  defp keep(rows, filters) do
    Enum.filter(rows, fn row ->
      Enum.all?(filters, fn
        {:environment_id, id} when is_binary(id) -> row.environment_id == id
        {:category, c} when is_atom(c) and not is_nil(c) -> row.category == c
        _ -> true
      end)
    end)
  end

  defp utc_range(from, to) do
    {local_midnight(from), local_midnight(Date.add(to, 1))}
  end

  defp local_midnight(day) do
    day |> DateTime.new!(~T[00:00:00]) |> DateTime.add(-@utc_offset_hours, :hour)
  end

  defp email_counts(metric, field, start_at, end_at) do
    Repo.all(
      from e in Email,
        where:
          field(e, ^field) >= ^start_at and field(e, ^field) < ^end_at and not is_nil(e.provider),
        group_by: [local_day(field(e, ^field)), e.environment_id, e.provider, e.category],
        select:
          {{local_day(field(e, ^field)), e.environment_id, e.provider, e.category}, count(e.id)}
    )
    |> Enum.map(fn {key, count} -> {key, metric, count} end)
  end

  defp recipient_counts(start_at, end_at) do
    Repo.all(
      from r in Recipient,
        join: e in assoc(r, :email),
        where:
          r.status in [:delivered, :bounced, :spam_complaint] and r.status_at >= ^start_at and
            r.status_at < ^end_at and not is_nil(e.provider),
        group_by: [
          local_day(r.status_at),
          e.environment_id,
          e.provider,
          e.category,
          r.status,
          r.bounce_kind
        ],
        select:
          {{local_day(r.status_at), e.environment_id, e.provider, e.category}, r.status,
           r.bounce_kind, count(r.id)}
    )
    |> Enum.map(fn {key, status, kind, count} -> {key, recipient_metric(status, kind), count} end)
  end

  defp recipient_metric(:delivered, _kind), do: :delivered
  defp recipient_metric(:spam_complaint, _kind), do: :spam
  defp recipient_metric(:bounced, :not_found), do: :not_found
  defp recipient_metric(:bounced, _kind), do: :bounced
end
