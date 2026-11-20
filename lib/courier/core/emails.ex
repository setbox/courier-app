defmodule Courier.Core.Emails do
  import Ecto.Query, warn: false

  alias Courier.Connectors.Brevo
  alias Courier.Core.Apps
  alias Courier.Core.Apps.{ChannelConfig, Environment}
  alias Courier.Core.Emails.{Email, Event, Recipient, Request}
  alias Courier.Core.Storage
  alias Courier.Core.Unsubscribes
  alias Courier.Core.Webhooks
  alias Courier.Repo
  alias Courier.Workers.SendEmail

  @idempotency_window_hours 24
  @retention_days 90
  @page_size 50
  @max_page_size 100

  def retention_days, do: @retention_days

  def submit(%Environment{} = environment, params, idempotency_key \\ nil) do
    config = Apps.email_config(environment)

    with :ok <- ensure_ready(config),
         {:ok, request} <- validate(params),
         :ok <- ensure_recipients_allowed(environment, request),
         :ok <- ensure_subscribed(environment, request) do
      if present?(idempotency_key) do
        submit_idempotent(environment, config, request, idempotency_key)
      else
        create(environment, config, request, nil)
      end
    end
  end

  defp ensure_ready(config) do
    if ChannelConfig.ready?(config), do: :ok, else: {:error, :provider_not_configured}
  end

  defp ensure_subscribed(environment, %Request{category: :marketing, to: to}) do
    case Unsubscribes.suppressed(environment, to) do
      [] -> :ok
      unsubscribed -> {:error, {:recipient_unsubscribed, unsubscribed}}
    end
  end

  defp ensure_subscribed(_environment, _request), do: :ok

  defp ensure_recipients_allowed(environment, request) do
    case Enum.reject(
           request.to ++ request.cc ++ request.bcc,
           &Environment.recipient_allowed?(environment, &1)
         ) do
      [] -> :ok
      blocked -> {:error, {:recipient_not_allowed, Enum.uniq(blocked)}}
    end
  end

  defp validate(params) do
    params
    |> Request.changeset()
    |> Ecto.Changeset.apply_action(:insert)
  end

  defp submit_idempotent(environment, config, request, key) do
    Repo.transact(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["#{environment.id}:#{key}"])

      case find_by_idempotency_key(environment, key) do
        %Email{} = email ->
          {:ok, {email, :replayed}}

        nil ->
          with {:ok, email} <- create(environment, config, request, key),
               do: {:ok, {email, :created}}
      end
    end)
    |> case do
      {:ok, {email, outcome}} -> {:ok, email, outcome}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_by_idempotency_key(environment, key) do
    since = DateTime.add(DateTime.utc_now(), -@idempotency_window_hours, :hour)

    Repo.one(
      from e in Email,
        where:
          e.environment_id == ^environment.id and e.idempotency_key == ^key and
            e.inserted_at > ^since,
        order_by: [desc: e.inserted_at],
        limit: 1,
        preload: [:recipients]
    )
  end

  defp create(environment, config, request, idempotency_key) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()
    body_key = body_key(environment, id, now)
    body = Jason.encode!(%{html_body: request.html_body, text_body: request.text_body})

    case Storage.put(body_key, body, "application/json") do
      :ok ->
        result = insert(environment, config, request, id, body_key, idempotency_key, now)

        with {:error, _} <- result, do: Storage.delete(body_key)

        result
        |> case do
          {:ok, email} when is_nil(idempotency_key) -> {:ok, email, :created}
          other -> other
        end

      {:error, _reason} ->
        {:error, :storage_unavailable}
    end
  end

  defp insert(environment, config, request, id, body_key, idempotency_key, now) do
    email = %Email{
      id: id,
      environment_id: environment.id,
      status: :queued,
      category: request.category,
      from: request.from || default_from(config),
      subject: request.subject,
      reply_to: request.reply_to,
      tag: request.tag,
      message_stream: request.message_stream || default_stream(config, request.category),
      metadata: request.metadata || %{},
      idempotency_key: idempotency_key,
      track_opens:
        if(is_nil(request.track_opens), do: config.track_opens, else: request.track_opens),
      track_links:
        if(is_nil(request.track_links), do: config.track_links, else: request.track_links),
      body_key: body_key,
      inserted_at: now,
      updated_at: now
    }

    Repo.transact(fn ->
      email = Repo.insert!(email)

      recipients =
        for {kind, list} <- [to: request.to, cc: request.cc, bcc: request.bcc],
            address <- list do
          Repo.insert!(%Recipient{email_id: email.id, kind: kind, address: address})
        end

      Repo.insert!(%Event{
        email_id: email.id,
        type: :queued,
        occurred_at: DateTime.truncate(now, :second)
      })

      Oban.insert!(SendEmail.new(%{email_id: email.id}))

      {:ok, %{email | recipients: recipients}}
    end)
  end

  defp default_stream(%ChannelConfig{provider: :postmark}, :marketing), do: "broadcast"
  defp default_stream(%ChannelConfig{message_stream: stream}, _category), do: stream

  defp default_from(%ChannelConfig{from_name: name, from_email: email}) when name in [nil, ""],
    do: email

  defp default_from(%ChannelConfig{from_name: name, from_email: email}),
    do: "#{String.replace(name, ~r/["<>]/, "")} <#{email}>"

  defp body_key(environment, id, now) do
    Enum.join(
      [
        environment.app_id,
        environment.id,
        Calendar.strftime(now, "%Y"),
        Calendar.strftime(now, "%m"),
        "#{id}.json"
      ],
      "/"
    )
  end

  def fetch_body(%Email{body_key: key}) do
    with {:ok, json} <- Storage.get(key),
         {:ok, %{} = body} <- Jason.decode(json) do
      {:ok, %{html_body: body["html_body"], text_body: body["text_body"]}}
    end
  end

  def get_email(%Environment{id: environment_id}, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Email{} = email <- Repo.get_by(Email, id: uuid, environment_id: environment_id) do
      Repo.preload(email, [:recipients])
    else
      _ -> nil
    end
  end

  def get_email!(id) do
    Email
    |> Repo.get!(id)
    |> Repo.preload([:recipients, events: [:recipient], environment: :app])
  end

  def list_events(%Email{id: email_id}) do
    Repo.all(
      from ev in Event,
        where: ev.email_id == ^email_id,
        order_by: [asc: ev.occurred_at, asc: ev.inserted_at],
        preload: [:recipient]
    )
  end

  def list_emails(filters, opts \\ []) do
    limit = page_size(opts[:limit])

    emails =
      Email
      |> filter(filters)
      |> after_cursor(opts[:cursor])
      |> order_by([e], desc: e.inserted_at, desc: e.id)
      |> limit(^(limit + 1))
      |> preload([:recipients, environment: :app])
      |> Repo.all()

    {page, rest} = Enum.split(emails, limit)
    next_cursor = if rest != [], do: encode_cursor(List.last(page))

    {page, next_cursor}
  end

  defp page_size(nil), do: @page_size

  defp page_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> page_size(number)
      _ -> @page_size
    end
  end

  defp page_size(value) when is_integer(value), do: value |> max(1) |> min(@max_page_size)

  defp filter(query, filters) do
    Enum.reduce(filters, query, fn
      {_key, value}, query when value in [nil, ""] ->
        query

      {:environment_id, id}, query ->
        where(query, [e], e.environment_id == ^id)

      {:app_id, id}, query ->
        from e in query,
          join: env in Environment,
          on: env.id == e.environment_id,
          where: env.app_id == ^id

      {:status, status}, query ->
        case cast_status(status) do
          nil -> where(query, false)
          status -> where(query, [e], e.status == ^status)
        end

      {:to, address}, query ->
        recipients =
          from r in Recipient, where: r.address == ^String.trim(address), select: r.email_id

        where(query, [e], e.id in subquery(recipients))

      {:idempotency_key, key}, query ->
        where(query, [e], e.idempotency_key == ^key)

      {:category, category}, query when category in [:transactional, :marketing] ->
        where(query, [e], e.category == ^category)

      {:metadata, metadata}, query when is_map(metadata) ->
        Enum.reduce(metadata, query, fn {key, value}, query ->
          where(query, [e], fragment("?->>? = ?", e.metadata, ^to_string(key), ^to_string(value)))
        end)

      {:from_date, date}, query ->
        case parse_datetime(date, :start) do
          nil -> where(query, false)
          datetime -> where(query, [e], e.inserted_at >= ^datetime)
        end

      {:to_date, date}, query ->
        case parse_datetime(date, :end) do
          nil -> where(query, false)
          datetime -> where(query, [e], e.inserted_at <= ^datetime)
        end

      _other, query ->
        query
    end)
  end

  defp cast_status(status) when is_atom(status), do: if(status in Email.statuses(), do: status)

  defp cast_status(status) when is_binary(status),
    do: Enum.find(Email.statuses(), &(Atom.to_string(&1) == status))

  defp cast_status(_status), do: nil

  defp parse_datetime(%DateTime{} = datetime, _edge), do: datetime

  defp parse_datetime(value, edge) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        case Date.from_iso8601(value) do
          {:ok, date} when edge == :start -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
          {:ok, date} -> DateTime.new!(date, ~T[23:59:59.999999], "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp parse_datetime(_value, _edge), do: nil

  defp after_cursor(query, cursor) when cursor in [nil, ""], do: query

  defp after_cursor(query, cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [timestamp, id] <- String.split(decoded, "|", parts: 2),
         {:ok, inserted_at, _} <- DateTime.from_iso8601(timestamp),
         {:ok, id} <- Ecto.UUID.cast(id) do
      where(
        query,
        [e],
        e.inserted_at < ^inserted_at or (e.inserted_at == ^inserted_at and e.id < ^id)
      )
    else
      _ -> where(query, false)
    end
  end

  defp encode_cursor(%Email{inserted_at: inserted_at, id: id}),
    do: Base.url_encode64("#{DateTime.to_iso8601(inserted_at)}|#{id}", padding: false)

  def record_unsubscribe(email_id, address) do
    case Repo.get(Email, email_id) do
      nil ->
        :ok

      email ->
        email = Repo.preload(email, :recipients)
        recipient = find_recipient(email, address)

        record_event!(email, :subscription_change, DateTime.utc_now(:second), recipient, %{
          "source" => "courier",
          "suppress_sending" => true
        })

        :ok
    end
  end

  def sandbox?(%Email{provider_message_id: "sandbox-" <> _}), do: true
  def sandbox?(%Email{}), do: false

  def mark_sent(%Email{} = email, message_id, provider \\ nil) do
    now = DateTime.utc_now(:second)

    Repo.transact(fn ->
      email =
        email
        |> Ecto.Changeset.change(
          status: :sent,
          provider: provider || email.provider,
          provider_message_id: message_id,
          sent_at: now,
          attempts: email.attempts + 1,
          error_code: nil,
          error_message: nil
        )
        |> Repo.update!()

      record_event!(email, :sent, now, nil, %{"provider_message_id" => message_id})
      {:ok, email}
    end)
  end

  def mark_failed(%Email{} = email, code, message, provider \\ nil) do
    now = DateTime.utc_now(:second)

    Repo.transact(fn ->
      email =
        email
        |> Ecto.Changeset.change(
          status: :failed,
          provider: provider || email.provider,
          failed_at: now,
          attempts: email.attempts + 1,
          error_code: code,
          error_message: message
        )
        |> Repo.update!()

      record_event!(email, :failed, now, nil, %{"error_code" => code, "error_message" => message})
      {:ok, email}
    end)
  end

  def register_attempt(%Email{} = email, message) do
    email
    |> Ecto.Changeset.change(attempts: email.attempts + 1, error_message: message)
    |> Repo.update!()
  end

  def apply_postmark_event(
        %Environment{} = environment,
        %{"RecordType" => type, "MessageID" => message_id} = payload
      )
      when is_binary(message_id) do
    with {:ok, event_type} <- event_type(type),
         %Email{} = email <- find_by_provider_message_id(environment, message_id) do
      Repo.transact(fn ->
        recipient = find_recipient(email, recipient_address(event_type, payload))
        occurred_at = occurred_at(event_type, payload)

        update_recipient(
          recipient,
          event_type,
          occurred_at,
          {bounce_detail(payload), postmark_bounce_kind(payload["Type"])}
        )

        event = record_event!(email, event_type, occurred_at, recipient, event_data(payload))

        {:ok, event}
      end)
    else
      :ignore -> {:ok, :ignored}
      nil -> {:ok, :unknown_message}
    end
  end

  def apply_postmark_event(_environment, _payload), do: {:ok, :ignored}

  def apply_brevo_event(
        %Environment{} = environment,
        %{"event" => type, "message-id" => message_id} = payload
      )
      when is_binary(message_id) do
    with {:ok, event_type} <- brevo_event_type(type),
         %Email{} = email <-
           find_by_provider_message_id(environment, Brevo.normalize_message_id(message_id)) do
      Repo.transact(fn ->
        recipient = find_recipient(email, payload["email"])
        occurred_at = brevo_occurred_at(payload)

        update_recipient(
          recipient,
          event_type,
          occurred_at,
          {brevo_bounce_detail(payload), brevo_bounce_kind(type)}
        )

        event = record_event!(email, event_type, occurred_at, recipient, payload)

        {:ok, event}
      end)
    else
      :ignore -> {:ok, :ignored}
      nil -> {:ok, :unknown_message}
    end
  end

  def apply_brevo_event(_environment, _payload), do: {:ok, :ignored}

  defp brevo_event_type("delivered"), do: {:ok, :delivery}

  defp brevo_event_type(type) when type in ["hard_bounce", "blocked", "invalid_email"],
    do: {:ok, :bounce}

  defp brevo_event_type("spam"), do: {:ok, :spam_complaint}
  defp brevo_event_type("opened"), do: {:ok, :open}
  defp brevo_event_type("click"), do: {:ok, :click}
  defp brevo_event_type("unsubscribed"), do: {:ok, :subscription_change}
  defp brevo_event_type(_type), do: :ignore

  defp brevo_occurred_at(payload) do
    case unix_seconds(payload["ts_event"] || payload["ts_epoch"] || payload["ts"]) do
      {:ok, datetime} -> datetime
      :error -> DateTime.utc_now(:second)
    end
  end

  defp unix_seconds(value) when is_integer(value) and value > 100_000_000_000,
    do: unix_seconds(div(value, 1000))

  defp unix_seconds(value) when is_integer(value) do
    case DateTime.from_unix(value) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp unix_seconds(_value), do: :error

  defp brevo_bounce_detail(payload) do
    [payload["event"], payload["reason"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(": ")
  end

  defp event_type("Delivery"), do: {:ok, :delivery}
  defp event_type("Bounce"), do: {:ok, :bounce}
  defp event_type("SpamComplaint"), do: {:ok, :spam_complaint}
  defp event_type("Open"), do: {:ok, :open}
  defp event_type("Click"), do: {:ok, :click}
  defp event_type("SubscriptionChange"), do: {:ok, :subscription_change}
  defp event_type(_type), do: :ignore

  defp find_by_provider_message_id(environment, message_id) do
    Repo.one(
      from e in Email,
        where: e.environment_id == ^environment.id and e.provider_message_id == ^message_id,
        preload: [:recipients]
    )
  end

  defp recipient_address(type, payload) when type in [:bounce, :spam_complaint],
    do: payload["Email"] || payload["Recipient"]

  defp recipient_address(_type, payload), do: payload["Recipient"] || payload["Email"]

  defp find_recipient(_email, nil), do: nil

  defp find_recipient(%Email{recipients: recipients}, address) do
    normalized = address |> Request.address_of() |> String.downcase()
    Enum.find(recipients, &(String.downcase(&1.address) == normalized))
  end

  defp occurred_at(type, payload) do
    field =
      case type do
        :delivery -> "DeliveredAt"
        type when type in [:bounce, :spam_complaint] -> "BouncedAt"
        type when type in [:open, :click] -> "ReceivedAt"
        :subscription_change -> "ChangedAt"
      end

    case payload[field] && DateTime.from_iso8601(payload[field]) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> DateTime.utc_now(:second)
    end
  end

  defp postmark_bounce_kind(type) when type in ["HardBounce", "BadEmailAddress"], do: :not_found
  defp postmark_bounce_kind(_type), do: :other

  defp brevo_bounce_kind(type) when type in ["hard_bounce", "invalid_email"], do: :not_found
  defp brevo_bounce_kind(_type), do: :other

  defp update_recipient(nil, _type, _at, _payload), do: :ok

  defp update_recipient(%Recipient{} = recipient, type, at, {bounce_detail, bounce_kind}) do
    changes =
      case type do
        :delivery -> status_change(recipient, :delivered, at, nil)
        :bounce -> bounce_change(recipient, at, bounce_detail, bounce_kind)
        :spam_complaint -> status_change(recipient, :spam_complaint, at, nil)
        :open -> if(is_nil(recipient.opened_at), do: [opened_at: at], else: [])
        :click -> if(is_nil(recipient.clicked_at), do: [clicked_at: at], else: [])
        :subscription_change -> []
      end

    if changes != [], do: recipient |> Ecto.Changeset.change(changes) |> Repo.update!()
    :ok
  end

  defp bounce_change(recipient, at, detail, kind) do
    case status_change(recipient, :bounced, at, detail) do
      [] -> []
      changes -> changes ++ [bounce_kind: kind]
    end
  end

  defp status_change(%Recipient{status: current}, new, at, detail) do
    if replaces?(current, new), do: [status: new, status_at: at, detail: detail], else: []
  end

  defp replaces?(:pending, _new), do: true
  defp replaces?(:delivered, new), do: new in [:bounced, :spam_complaint]
  defp replaces?(:bounced, :spam_complaint), do: true
  defp replaces?(_current, _new), do: false

  defp bounce_detail(payload) do
    [payload["Type"], payload["Description"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(": ")
  end

  defp event_data(payload), do: Map.drop(payload, ["Content", "Metadata"])

  defp record_event!(%Email{} = email, type, occurred_at, recipient, data) do
    event =
      Repo.insert!(%Event{
        email_id: email.id,
        recipient_id: recipient && recipient.id,
        type: type,
        occurred_at: occurred_at,
        data: data
      })

    Webhooks.enqueue(email, event)
    event
  end

  @failure_types [:failed, :not_found, :bounced, :spam]

  def failure_types, do: @failure_types

  def list_failures(filters, limit) do
    types = if filters[:type] in @failure_types, do: [filters[:type]], else: @failure_types

    failed =
      if :failed in types,
        do:
          filters
          |> failed_emails_query()
          |> order_by([e], desc: e.failed_at)
          |> preload([:recipients, environment: :app])
          |> limit(^limit)
          |> Repo.all(),
        else: []

    recipients =
      case List.delete(types, :failed) do
        [] ->
          []

        kinds ->
          filters
          |> failed_recipients_query(kinds)
          |> order_by([r], desc: r.status_at)
          |> preload([email: e], email: {e, environment: :app})
          |> limit(^limit)
          |> Repo.all()
      end

    (Enum.map(failed, &failure_from_email/1) ++ Enum.map(recipients, &failure_from_recipient/1))
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  def count_failures(filters) do
    failed = filters |> failed_emails_query() |> Repo.aggregate(:count)

    by_kind =
      filters
      |> failed_recipients_query([:not_found, :bounced, :spam])
      |> group_by([r], [r.status, r.bounce_kind])
      |> select([r], {r.status, r.bounce_kind, count(r.id)})
      |> Repo.all()
      |> Enum.reduce(%{not_found: 0, bounced: 0, spam: 0}, fn {status, kind, count}, acc ->
        Map.update!(acc, failure_type(status, kind), &(&1 + count))
      end)

    Map.put(by_kind, :failed, failed)
  end

  defp failed_emails_query(filters) do
    from(e in Email,
      as: :failed_email,
      where: e.status == :failed and e.failed_at >= ^filters.since
    )
    |> failure_filters(filters, :email)
  end

  defp failed_recipients_query(filters, kinds) do
    from(r in Recipient,
      join: e in assoc(r, :email),
      as: :email,
      where: r.status in [:bounced, :spam_complaint] and r.status_at >= ^filters.since,
      where: ^kinds_condition(kinds)
    )
    |> failure_filters(filters, :recipient)
  end

  defp kinds_condition(kinds) do
    Enum.reduce(kinds, dynamic(false), fn
      :spam, acc ->
        dynamic([r], ^acc or r.status == :spam_complaint)

      :not_found, acc ->
        dynamic([r], ^acc or (r.status == :bounced and r.bounce_kind == :not_found))

      :bounced, acc ->
        dynamic(
          [r],
          ^acc or
            (r.status == :bounced and (is_nil(r.bounce_kind) or r.bounce_kind != :not_found))
        )
    end)
  end

  defp failure_filters(query, filters, source) do
    Enum.reduce(filters, query, fn
      {:environment_id, id}, q when is_binary(id) ->
        where(q, ^environment_condition(source, id))

      {:provider, p}, q when is_atom(p) and not is_nil(p) ->
        where(q, ^provider_condition(source, p))

      {:q, term}, q when is_binary(term) and term != "" ->
        where_address(q, source, "%#{term}%")

      _, q ->
        q
    end)
  end

  defp environment_condition(:email, id), do: dynamic([e], e.environment_id == ^id)
  defp environment_condition(:recipient, id), do: dynamic([email: e], e.environment_id == ^id)

  defp provider_condition(:email, provider), do: dynamic([e], e.provider == ^provider)
  defp provider_condition(:recipient, provider), do: dynamic([email: e], e.provider == ^provider)

  defp where_address(query, :email, pattern) do
    where(
      query,
      [e],
      exists(
        from r in Recipient,
          where: r.email_id == parent_as(:failed_email).id and ilike(r.address, ^pattern)
      )
    )
  end

  defp where_address(query, :recipient, pattern),
    do: where(query, [r], ilike(r.address, ^pattern))

  defp failure_type(:spam_complaint, _kind), do: :spam
  defp failure_type(:bounced, :not_found), do: :not_found
  defp failure_type(:bounced, _kind), do: :bounced

  defp failure_from_email(%Email{} = email) do
    %{
      id: "email-#{email.id}",
      type: :failed,
      at: email.failed_at,
      email: email,
      address: Enum.map_join(email.recipients, ", ", & &1.address),
      reason: email.error_message
    }
  end

  defp failure_from_recipient(%Recipient{email: email} = recipient) do
    %{
      id: "recipient-#{recipient.id}",
      type: failure_type(recipient.status, recipient.bounce_kind),
      at: recipient.status_at,
      email: email,
      address: recipient.address,
      reason:
        recipient.detail ||
          if(recipient.status == :spam_complaint, do: "O destinatário marcou como spam")
    }
  end

  def purge_expired(batch_size \\ 500) do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days, :day)
    purge_batch(cutoff, batch_size, 0)
  end

  defp purge_batch(cutoff, batch_size, total) do
    batch =
      Repo.all(
        from e in Email,
          where: e.inserted_at < ^cutoff,
          select: {e.id, e.body_key},
          limit: ^batch_size
      )

    Enum.each(batch, fn {_id, key} -> Storage.delete(key) end)
    ids = Enum.map(batch, &elem(&1, 0))
    {deleted, _} = Repo.delete_all(from e in Email, where: e.id in ^ids)

    if length(batch) == batch_size,
      do: purge_batch(cutoff, batch_size, total + deleted),
      else: total + deleted
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
