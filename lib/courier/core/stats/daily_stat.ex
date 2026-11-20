defmodule Courier.Core.Stats.DailyStat do
  use Ecto.Schema

  alias Courier.Core.Apps.{ChannelConfig, Environment}
  alias Courier.Core.Emails.Email

  @metrics [:sent, :delivered, :failed, :not_found, :bounced, :spam]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "email_daily_stats" do
    field :day, :date
    field :provider, Ecto.Enum, values: ChannelConfig.providers()
    field :category, Ecto.Enum, values: Email.categories()
    field :sent, :integer, default: 0
    field :delivered, :integer, default: 0
    field :failed, :integer, default: 0
    field :not_found, :integer, default: 0
    field :bounced, :integer, default: 0
    field :spam, :integer, default: 0

    belongs_to :environment, Environment

    timestamps(type: :utc_datetime)
  end

  def metrics, do: @metrics
end
