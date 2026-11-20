defmodule Courier.MCP.Server do
  use Anubis.Server,
    name: "courier",
    version: "0.1.0",
    capabilities: [:tools],
    protocol_versions: Anubis.Protocol.Registry.supported_versions()

  alias Courier.MCP.Tools

  component(Tools.GetDashboard)
  component(Tools.ListFailures)
  component(Tools.ListEmails)
  component(Tools.GetEmail)
  component(Tools.ListApps)
  component(Tools.GetApp)
  component(Tools.GetEnvironment)
  component(Tools.ListProviders)
  component(Tools.ListUnsubscribes)
  component(Tools.SearchAudit)
  component(Tools.SendTestEmail)
  component(Tools.RedeliverWebhook)
  component(Tools.CreateApp)
  component(Tools.CreateEnvironment)
  component(Tools.UpdateRecipientLists)
  component(Tools.RemoveUnsubscribe)
  component(Tools.ConfigureEmail)
  component(Tools.GenerateClientToken)

  @impl true
  def init(_client_info, frame), do: {:ok, frame}

  def authorization_config do
    [
      authorization_servers: [Courier.OAuth.issuer()],
      resource: resource(),
      realm: "courier",
      scopes_supported: [Courier.OAuth.scope()],
      validator: {Courier.MCP.TokenValidator, []}
    ]
  end

  def resource do
    Application.get_env(:courier, :mcp_resource) || default_resource()
  end

  defp default_resource do
    config = Application.get_env(:courier, CourierWeb.Endpoint, [])
    url = Keyword.get(config, :url, [])

    scheme = Keyword.get(url, :scheme, "http")
    host = Keyword.get(url, :host, "localhost")
    port = Keyword.get(url, :port) || config |> Keyword.get(:http, []) |> Keyword.get(:port, 4012)

    authority =
      if (scheme == "https" and port == 443) or (scheme == "http" and port == 80),
        do: host,
        else: "#{host}:#{port}"

    "#{scheme}://#{authority}/mcp"
  end
end
