defmodule CourierWeb.Format do
  @offset_seconds -3 * 60 * 60

  def datetime(nil), do: "-"

  def datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.add(@offset_seconds, :second)
    |> Calendar.strftime("%d/%m/%Y %H:%M:%S")
  end

  def email_status(:queued), do: "Na fila"
  def email_status(:sent), do: "Enviado"
  def email_status(:failed), do: "Falhou"

  def recipient_status(:pending), do: "Aguardando"
  def recipient_status(:delivered), do: "Entregue"
  def recipient_status(:bounced), do: "Devolvido"
  def recipient_status(:spam_complaint), do: "Marcado como spam"

  def event_type(:queued), do: "Recebido"
  def event_type(:sent), do: "Enviado ao Postmark"
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
