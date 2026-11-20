defmodule CourierWeb.Format do
  @offset_seconds -3 * 60 * 60

  def datetime(nil), do: "-"

  def datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.add(@offset_seconds, :second)
    |> Calendar.strftime("%d/%m/%Y %H:%M:%S")
  end

  def number(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  def percent(_part, 0), do: "0%"

  def percent(part, total) do
    ratio = part / total * 100
    decimals = if ratio < 10, do: 2, else: 1

    (ratio
     |> Float.round(decimals)
     |> :erlang.float_to_binary(decimals: decimals)
     |> String.replace(".", ",")) <> "%"
  end

  def short_datetime(nil), do: "-"

  def short_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.add(@offset_seconds, :second)
    |> Calendar.strftime("%d/%m %H:%M")
  end

  def category(:transactional), do: "Transacional"
  def category(:marketing), do: "Marketing"

  def email_status(:queued), do: "Na fila"
  def email_status(:sent), do: "Enviado"
  def email_status(:failed), do: "Falhou"

  def recipient_status(:pending), do: "Aguardando"
  def recipient_status(:delivered), do: "Entregue"
  def recipient_status(:bounced), do: "Devolvido"
  def recipient_status(:spam_complaint), do: "Marcado como spam"

  def event_type(:queued), do: "Recebido"
  def event_type(:sent), do: "Enviado ao provider"
  def event_type(:failed), do: "Falhou"
  def event_type(:delivery), do: "Entregue"
  def event_type(:bounce), do: "Devolvido"
  def event_type(:spam_complaint), do: "Marcado como spam"
  def event_type(:open), do: "Aberto"
  def event_type(:click), do: "Clique"
  def event_type(:subscription_change), do: "Mudança de inscrição"

  def delivery_status(:pending), do: "Pendente"
  def delivery_status(:delivered), do: "Entregue"
  def delivery_status(:failed), do: "Falhou"

  def tone(status) when status in [:sent, :delivered], do: :ok
  def tone(status) when status in [:failed, :bounced, :spam_complaint], do: :error
  def tone(:queued), do: :pending
  def tone(_status), do: :neutral
end
