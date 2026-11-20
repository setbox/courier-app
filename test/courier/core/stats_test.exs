defmodule Courier.Core.StatsTest do
  use Courier.DataCase, async: true

  import Courier.MessagingFixtures

  alias Courier.Core.{Emails, Stats}
  alias Courier.Core.Stats.DailyStat

  setup do
    {environment, _token} = configured_environment_fixture()
    %{environment: environment}
  end

  defp sent_email(environment, attrs \\ %{}) do
    email = email_fixture(environment, attrs)
    {:ok, email} = Emails.mark_sent(Repo.preload(email, :recipients), "pm-#{email.id}", :postmark)
    email
  end

  test "counts sent, failed, delivered, not found, bounced and spam for today", %{
    environment: environment
  } do
    delivered = sent_email(environment)
    not_found = sent_email(environment)
    bounced = sent_email(environment, %{"category" => "marketing"})
    spam = sent_email(environment)
    failed = email_fixture(environment)
    {:ok, _} = Emails.mark_failed(failed, 422, "rejected", :postmark)

    event = fn email, attrs ->
      Emails.apply_postmark_event(
        environment,
        Map.merge(
          %{"MessageID" => email.provider_message_id, "Recipient" => "ana@exemplo.com.br"},
          attrs
        )
      )
    end

    {:ok, _} = event.(delivered, %{"RecordType" => "Delivery"})

    {:ok, _} =
      event.(not_found, %{
        "RecordType" => "Bounce",
        "Type" => "HardBounce",
        "Email" => "ana@exemplo.com.br"
      })

    {:ok, _} =
      event.(bounced, %{
        "RecordType" => "Bounce",
        "Type" => "Blocked",
        "Email" => "ana@exemplo.com.br"
      })

    {:ok, _} = event.(spam, %{"RecordType" => "SpamComplaint", "Email" => "ana@exemplo.com.br"})

    rows = Stats.aggregate(Stats.today(), Stats.today())
    totals = Map.new(DailyStat.metrics(), fn m -> {m, Enum.sum_by(rows, &Map.fetch!(&1, m))} end)

    assert totals == %{sent: 4, failed: 1, delivered: 1, not_found: 1, bounced: 1, spam: 1}
    assert Enum.all?(rows, &(&1.provider == :postmark and &1.environment_id == environment.id))
    assert Enum.find(rows, &(&1.category == :marketing)).bounced == 1
  end

  test "series merges stored days with today and filters by category", %{
    environment: environment
  } do
    sent_email(environment)
    sent_email(environment, %{"category" => "marketing"})
    yesterday = Date.add(Stats.today(), -1)

    Repo.insert!(%DailyStat{
      day: yesterday,
      environment_id: environment.id,
      provider: :brevo,
      category: :transactional,
      sent: 5,
      delivered: 4
    })

    series = Stats.series(:days_7)
    assert length(series.buckets) == 7
    assert series.totals.sent == 7
    assert List.last(series.points).sent == 2
    assert series.by_provider[:brevo] |> Enum.sum() == 5

    assert Stats.series(:days_7, %{category: :marketing}).totals.sent == 1
    assert length(Stats.series(:months_12).buckets) == 12
  end

  test "rebuild stores closed days and replaces them on the next run", %{environment: environment} do
    yesterday = Date.add(Stats.today(), -1)

    Repo.insert!(%DailyStat{
      day: yesterday,
      environment_id: environment.id,
      provider: :postmark,
      category: :transactional,
      sent: 99
    })

    assert {:ok, 0} = Stats.rebuild(yesterday, yesterday)
    refute Repo.exists?(DailyStat)
  end
end
