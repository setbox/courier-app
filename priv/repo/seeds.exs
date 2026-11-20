alias Courier.Core.Accounts

admin_email =
  case System.get_env("ADMIN_EMAIL") do
    value when value in [nil, ""] -> "jackson@setbox.com.br"
    value -> value
  end

case Accounts.ensure_admin(admin_email) do
  {:created, user} -> IO.puts("Administrador criado: #{user.email} (entra pelo Google)")
  {:existing, user} -> IO.puts("Administrador já existe: #{user.email}")
end

case Courier.Core.Storage.ensure_bucket!() do
  :ok -> IO.puts("Bucket #{Courier.Core.Storage.bucket()} pronto")
end
