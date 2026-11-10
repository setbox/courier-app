defmodule Courier.Core.Accounts.UserNotifier do
  import Swoosh.Email

  alias Courier.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:courier, :mail_from))
      |> reply_to(Application.fetch_env!(:courier, :mail_reply_to))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirme seu novo e-mail", """
    Olá!

    Para confirmar a troca do seu e-mail no Courier, acesse o link abaixo:

    #{url}

    Se você não pediu essa troca, ignore esta mensagem: nada muda.
    """)
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirme sua conta no Courier", """
    Olá!

    Falta um passo para usar o Courier: confirme este e-mail. O link vale por 7 dias.

    #{url}

    Se você não criou uma conta no Courier, ignore esta mensagem.
    """)
  end

  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Redefinir sua senha no Courier", """
    Olá!

    Para escolher uma senha nova, acesse o link abaixo. Ele vale por 24 horas e só funciona uma vez.

    #{url}

    Se você não pediu a troca, ignore esta mensagem: sua senha continua a mesma.
    """)
  end
end
