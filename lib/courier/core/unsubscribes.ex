defmodule Courier.Core.Unsubscribes do
  import Ecto.Query, warn: false

  alias Courier.Core.Apps.Environment
  alias Courier.Core.Emails
  alias Courier.Core.Emails.Email
  alias Courier.Core.Unsubscribes.Suppression
  alias Courier.Repo

  @salt "courier unsubscribe"
  @max_age 2 * 365 * 24 * 60 * 60
  @placeholder "{{courier_unsubscribe_url}}"

  def placeholder, do: @placeholder

  def url(%Email{} = email, address) do
    token =
      Phoenix.Token.sign(secret(), @salt, %{
        "e" => email.id,
        "v" => email.environment_id,
        "a" => address
      })

    CourierWeb.Endpoint.url() <> "/u/" <> token
  end

  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(secret(), @salt, token, max_age: @max_age) do
      {:ok, %{"e" => email_id, "v" => environment_id, "a" => address}} ->
        {:ok, %{email_id: email_id, environment_id: environment_id, address: address}}

      _ ->
        :error
    end
  end

  def verify(_token), do: :error

  def unsubscribe(token) do
    with {:ok, %{email_id: email_id, environment_id: environment_id, address: address}} <-
           verify(token),
         %Environment{} <- Repo.get(Environment, environment_id) do
      address = String.downcase(address)

      unless Repo.exists?(
               from s in Suppression,
                 where: s.environment_id == ^environment_id and s.address == ^address
             ) do
        email_id = if Repo.get(Email, email_id), do: email_id

        Repo.insert!(
          %Suppression{environment_id: environment_id, address: address, email_id: email_id},
          on_conflict: :nothing,
          conflict_target: [:environment_id, :address]
        )

        if email_id, do: Emails.record_unsubscribe(email_id, address)
      end

      {:ok, address}
    else
      _ -> :error
    end
  end

  def suppressed(%Environment{id: environment_id}, addresses) do
    normalized = Enum.map(addresses, &String.downcase/1)

    found =
      Repo.all(
        from s in Suppression,
          where: s.environment_id == ^environment_id and s.address in ^normalized,
          select: s.address
      )

    Enum.filter(addresses, &(String.downcase(&1) in found))
  end

  def list(%Environment{id: environment_id}, limit) do
    Repo.all(
      from s in Suppression,
        where: s.environment_id == ^environment_id,
        order_by: [desc: s.inserted_at],
        limit: ^limit
    )
  end

  def remove(%Environment{id: environment_id}, address) when is_binary(address) do
    address = address |> String.trim() |> String.downcase()

    case Repo.delete_all(
           from s in Suppression,
             where: s.environment_id == ^environment_id and s.address == ^address
         ) do
      {1, _} -> {:ok, address}
      {0, _} -> {:error, :not_found}
    end
  end

  def count(%Environment{id: environment_id}) do
    Repo.aggregate(from(s in Suppression, where: s.environment_id == ^environment_id), :count)
  end

  def with_link(nil, _url, _kind), do: nil

  def with_link(body, url, kind) do
    if String.contains?(body, @placeholder),
      do: String.replace(body, @placeholder, url),
      else: append_link(body, url, kind)
  end

  defp append_link(body, url, :html) do
    footer =
      ~s(<p style="font-size:12px;color:#666666">Para não receber mais estes e-mails, ) <>
        ~s(<a href="#{url}">cancele a inscrição</a>.</p>)

    if String.contains?(body, "</body>"),
      do: String.replace(body, "</body>", footer <> "</body>", global: false),
      else: body <> footer
  end

  defp append_link(body, url, :text),
    do: body <> "\n\nPara não receber mais estes e-mails, cancele a inscrição: " <> url

  defp secret, do: Application.fetch_env!(:courier, CourierWeb.Endpoint)[:secret_key_base]
end
