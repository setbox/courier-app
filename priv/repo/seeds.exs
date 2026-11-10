alias Courier.Core.Accounts

env = fn name ->
  case System.get_env(name) do
    value when value in [nil, ""] -> nil
    value -> value
  end
end

admin_email = env.("ADMIN_EMAIL") || "jackson@setbox.com.br"

admin_password =
  env.("ADMIN_PASSWORD") || if(Application.get_env(:courier, :env) == :dev, do: "root@Setbox")

case Accounts.ensure_admin(admin_email, admin_password) do
  {:created, user, password} ->
    IO.puts("Administrador criado: #{user.email} / #{password}")

  {:password_set, user, password} ->
    IO.puts("Senha definida para #{user.email}: #{password}")

  {:existing, user} ->
    IO.puts("Administrador já existe: #{user.email}")
end

case Courier.Core.Storage.ensure_bucket!() do
  :ok -> IO.puts("Bucket #{Courier.Core.Storage.bucket()} pronto")
end
