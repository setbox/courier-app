defmodule Courier.MCPHelpers do
  alias Anubis.Server.{Context, Frame, InputRequired, Response}

  def frame(user, opts \\ []) do
    {protocol, version} =
      case Keyword.get(opts, :era, :legacy) do
        :legacy -> {Anubis.Protocol.V2025_06_18, "2025-06-18"}
        :stateless -> {Anubis.Protocol.V2026_07_28, "2026-07-28"}
      end

    capabilities = if opts[:elicitation], do: %{"elicitation" => %{}}, else: %{}

    %Frame{
      context: %Context{
        auth: %{sub: user.id, raw_claims: %{"connection" => "Claude"}},
        protocol_module: protocol,
        protocol_version: version,
        client_capabilities: capabilities,
        input_responses: Keyword.get(opts, :responses, %{})
      }
    }
  end

  def call(tool, params, frame) do
    case tool.execute(params, frame) do
      {:reply, %Response{isError: false} = response, _frame} -> {:ok, decode(response)}
      {:reply, %Response{isError: true} = response, _frame} -> {:error, text(response)}
      {:reply, %InputRequired{} = input, _frame} -> {:input_required, input}
    end
  end

  def accept(content), do: %{"confirmacao" => %{"action" => "accept", "content" => content}}
  def decline, do: %{"confirmacao" => %{"action" => "decline"}}

  defp decode(response), do: response |> text() |> Jason.decode!()

  defp text(%Response{content: [%{"text" => text} | _]}), do: text
end
