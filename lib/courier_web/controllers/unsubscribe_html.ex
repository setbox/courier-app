defmodule CourierWeb.UnsubscribeHTML do
  use CourierWeb, :html

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="pt-BR">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex" />
        <title>{@title}</title>
        <link rel="stylesheet" href={~p"/assets/css/app.css"} />
      </head>
      <body class="bg-base-200">
        <main class="flex min-h-screen items-center justify-center px-4 py-10">
          <section class="w-full max-w-md space-y-4 rounded-box border border-base-300 bg-base-100 p-6">
            {render_slot(@inner_block)}
          </section>
        </main>
      </body>
    </html>
    """
  end

  def show(assigns) do
    ~H"""
    <.page title="Cancelar inscrição">
      <h1 class="text-xl font-semibold">Cancelar inscrição</h1>
      <p class="text-sm text-neutral">
        <span class="font-semibold text-base-content">{@address}</span>
        deixa de receber e-mails de marketing deste remetente. Os e-mails de conta e de pedidos continuam chegando.
      </p>
      <form method="post" action={~p"/u/#{@token}"} class="flex justify-end">
        <button type="submit" class="btn btn-primary">Cancelar inscrição</button>
      </form>
    </.page>
    """
  end

  def done(assigns) do
    ~H"""
    <.page title="Inscrição cancelada">
      <h1 class="text-xl font-semibold">Inscrição cancelada</h1>
      <p class="text-sm text-neutral">
        <span class="font-semibold text-base-content">{@address}</span>
        não recebe mais e-mails de marketing deste remetente.
      </p>
    </.page>
    """
  end

  def invalid(assigns) do
    ~H"""
    <.page title="Link inválido">
      <h1 class="text-xl font-semibold">Link inválido ou expirado</h1>
      <p class="text-sm text-neutral">
        Use o link de um e-mail mais recente para cancelar a inscrição.
      </p>
    </.page>
    """
  end
end
