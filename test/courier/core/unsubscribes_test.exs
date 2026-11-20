defmodule Courier.Core.UnsubscribesTest do
  use Courier.DataCase, async: true
  use Oban.Testing, repo: Courier.Repo

  import Courier.MessagingFixtures

  alias Courier.Core.{Emails, Unsubscribes}
  alias Courier.Core.Emails.Event
  alias Courier.Workers.SendEmail

  setup do
    {environment, _token} = configured_environment_fixture()
    %{environment: environment}
  end

  defp marketing(environment, attrs \\ %{}) do
    email_fixture(environment, Map.merge(%{"category" => "marketing"}, attrs))
  end

  test "marketing goes to a single recipient, without cc or bcc", %{environment: environment} do
    {:error, changeset} =
      Emails.submit(
        environment,
        email_params(%{
          "category" => "marketing",
          "to" => ["a@exemplo.com.br", "b@exemplo.com.br"],
          "cc" => ["c@exemplo.com.br"]
        })
      )

    errors = errors_on(changeset)
    assert errors.to == ["marketing goes to one recipient per email"]
    assert errors.cc == ["marketing does not accept cc"]
  end

  test "a signed link unsubscribes the recipient and blocks only marketing", %{
    environment: environment
  } do
    email = marketing(environment)
    url = Unsubscribes.url(email, "ana@exemplo.com.br")
    token = url |> String.split("/u/") |> List.last()

    assert {:ok, %{address: "ana@exemplo.com.br"}} = Unsubscribes.verify(token)
    assert {:ok, "ana@exemplo.com.br"} = Unsubscribes.unsubscribe(token)
    assert {:ok, "ana@exemplo.com.br"} = Unsubscribes.unsubscribe(token)
    assert Unsubscribes.count(environment) == 1
    assert Repo.get_by(Event, email_id: email.id, type: :subscription_change)

    assert {:error, {:recipient_unsubscribed, ["ANA@exemplo.com.br"]}} =
             Emails.submit(
               environment,
               email_params(%{"category" => "marketing", "to" => ["ANA@exemplo.com.br"]})
             )

    assert {:ok, _email, :created} = Emails.submit(environment, email_params())
    assert Unsubscribes.verify("forged") == :error
  end

  test "the worker adds the link to the body and the one-click headers", %{
    environment: environment
  } do
    email =
      marketing(environment, %{
        "html_body" => "<p>Oferta</p><p><a href=\"{{courier_unsubscribe_url}}\">sair</a></p>",
        "text_body" => "Oferta"
      })

    assert :ok = perform_job(SendEmail, %{email_id: email.id})

    json =
      Enum.find_value(Stream.repeatedly(fn -> receive_postmark() end), fn opts ->
        opts[:url] == "https://postmark.test/email" && opts[:json]
      end)

    assert json["MessageStream"] == "broadcast"

    assert [
             %{"Name" => "List-Unsubscribe", "Value" => "<" <> _},
             %{"Name" => "List-Unsubscribe-Post"}
           ] = json["Headers"]

    refute json["HtmlBody"] =~ "{{courier_unsubscribe_url}}"
    assert json["HtmlBody"] =~ "/u/"
    assert json["TextBody"] =~ "cancele a inscrição: http"
  end

  defp receive_postmark do
    receive do
      {:postmark_request, opts} -> opts
    after
      100 -> flunk("Postmark was not called")
    end
  end
end
