defmodule Courier.MCP do
  alias Anubis.Server.{Frame, InputRequired, Response}
  alias Courier.Core.{Accounts, Audit}
  alias Courier.Core.Accounts.User

  @confirm_key "confirmacao"
  @reason_field %{"type" => "string", "title" => "Motivo", "minLength" => 3, "maxLength" => 500}
  @confirm_field %{"type" => "boolean", "title" => "Confirmo"}

  def current_user(frame) do
    with id when not is_nil(id) <- Frame.subject(frame),
         %User{} = user <- get_user(id) do
      {:ok, user}
    else
      _ -> {:error, "Token sem acesso: a conta não existe mais."}
    end
  end

  defp get_user(id) do
    Accounts.get_user!(id)
  rescue
    Ecto.NoResultsError -> nil
    Ecto.Query.CastError -> nil
  end

  def with_user(frame, fun) do
    case current_user(frame) do
      {:ok, user} ->
        try do
          fun.(user)
        rescue
          Ecto.NoResultsError -> error(frame, "Registro não encontrado.")
          Ecto.Query.CastError -> error(frame, "Identificador inválido.")
        end

      {:error, message} ->
        error(frame, message)
    end
  end

  def reply(frame, data), do: {:reply, Response.json(Response.tool(), data), frame}

  def error(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}

  def arg(params, key) when is_atom(key) do
    case Map.fetch(params, key) do
      {:ok, value} -> value
      :error -> Map.get(params, Atom.to_string(key))
    end
  end

  def page(params, default \\ 50, max \\ 200) do
    case arg(params, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, max)
      _ -> default
    end
  end

  def write(frame, user, params, spec) do
    case Frame.input_response(frame, @confirm_key) do
      %{"action" => "accept", "content" => content} when is_map(content) ->
        accepted(frame, user, params, spec, content)

      %{"action" => action} when action in ["decline", "cancel"] ->
        cancelled(frame)

      _not_yet ->
        if elicitation?(frame),
          do: elicit(frame, spec),
          else: without_form(frame, user, params, spec)
    end
  end

  defp accepted(frame, user, params, spec, %{"motivo" => motivo})
       when is_binary(motivo) and motivo != "",
       do: execute(frame, user, params, spec, motivo)

  defp accepted(frame, _user, _params, _spec, _content), do: cancelled(frame)

  defp cancelled(frame) do
    reply(frame, %{status: "cancelado", detalhe: "A pessoa não confirmou. Nada mudou."})
  end

  defp elicit(frame, spec) do
    input =
      InputRequired.elicit(InputRequired.new(), @confirm_key, spec.message, %{
        "type" => "object",
        "properties" => %{"motivo" => @reason_field, "confirmar" => @confirm_field},
        "required" => ["motivo"]
      })

    {:reply, input, frame}
  end

  defp without_form(frame, user, params, spec) do
    motivo = arg(params, :reason)

    cond do
      blank?(motivo) ->
        error(
          frame,
          "Pergunte à pessoa o motivo (#{spec.message}) e chame de novo com reason e confirm: true."
        )

      arg(params, :confirm) == true ->
        execute(frame, user, params, spec, motivo)

      true ->
        error(
          frame,
          "Esta ação precisa de confirmação. Mostre à pessoa o que vai acontecer " <>
            "(#{spec.message}) e, só depois que ela confirmar, chame de novo com confirm: true."
        )
    end
  end

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""

  defp execute(frame, user, params, spec, motivo) do
    case spec.run.() do
      {:ok, data} ->
        Audit.record("mcp_write", user, %{
          "ferramenta" => spec.tool,
          "acao" => spec.message,
          "motivo" => motivo,
          "parametros" => audited_params(params)
        })

        reply(frame, Map.put(data, :status, "ok"))

      {:error, reason} ->
        error(frame, error_text(reason))
    end
  end

  defp audited_params(params) do
    params
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.drop(["confirm", "reason"])
  end

  def elicitation?(%Frame{context: context} = frame) do
    Anubis.Server.Stateless.era(context.protocol_module) == :stateless and
      Frame.client_supports?(frame, "elicitation")
  end

  def error_text(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{field}: #{Enum.join(List.wrap(messages), ", ")}"
    end)
  end

  def error_text(:not_found), do: "Registro não encontrado."

  def error_text(:provider_not_configured),
    do: "O ambiente não tem provider de e-mail configurado."

  def error_text(:storage_unavailable), do: "O armazenamento do corpo falhou. Tente de novo."

  def error_text({:recipient_not_allowed, addresses}),
    do: "Destinatário fora das listas do ambiente: #{Enum.join(addresses, ", ")}."

  def error_text({:recipient_unsubscribed, addresses}),
    do: "Destinatário descadastrado do marketing: #{Enum.join(addresses, ", ")}."

  def error_text(text) when is_binary(text), do: text
  def error_text(reason), do: "Não foi possível concluir: #{inspect(reason)}"

  def ok({:ok, value}, fun), do: {:ok, fun.(value)}
  def ok({:error, reason}, _fun), do: {:error, reason}
end
