defmodule CourierWeb.OAuthServerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.Core.AccountsFixtures

  alias Courier.Core.Accounts
  alias Courier.OAuth

  @redirect_uri "https://claude.ai/api/mcp/auth_callback"
  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk-abcdefghijklmnop"

  defp challenge(verifier \\ @verifier),
    do: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

  defp register_client do
    {:ok, client, _secret} =
      OAuth.register_client(%{"client_name" => "Claude", "redirect_uris" => [@redirect_uri]})

    client
  end

  defp authorize_params(client) do
    %{
      "client_id" => client.id,
      "redirect_uri" => @redirect_uri,
      "response_type" => "code",
      "state" => "xyz",
      "code_challenge" => challenge(),
      "code_challenge_method" => "S256",
      "scope" => "mcp"
    }
  end

  defp query_from(conn) do
    location = redirected_to(conn)
    assert String.starts_with?(location, @redirect_uri)
    URI.decode_query(URI.parse(location).query)
  end

  test "publishes the metadata and registers a public client", %{conn: conn} do
    body = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)
    assert body["authorization_endpoint"] =~ "/oauth/authorize"
    assert body["code_challenge_methods_supported"] == ["S256"]

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/oauth/register",
        Jason.encode!(%{"client_name" => "Claude", "redirect_uris" => [@redirect_uri]})
      )

    assert json_response(conn, 201)["client_id"]

    refused = post(build_conn(), "/oauth/register", %{"redirect_uris" => ["http://evil.test/cb"]})
    assert %{"error" => "invalid_redirect_uri"} = json_response(refused, 400)
  end

  test "sends a signed-out person to login and back to the consent screen", %{conn: conn} do
    client = register_client()
    conn = get(conn, "/oauth/authorize", authorize_params(client))

    assert redirected_to(conn) == ~p"/login"
    assert get_session(conn, :user_return_to) =~ "/oauth/authorize?"
  end

  test "consent, code and token: the full flow gives a working MCP token", %{conn: conn} do
    client = register_client()
    user = user_fixture()
    conn = log_in_user(conn, user)

    html = conn |> get("/oauth/authorize", authorize_params(client)) |> html_response(200)
    assert html =~ "Conectar Claude?"

    query =
      conn
      |> post("/oauth/authorize", Map.put(authorize_params(client), "decision", "allow"))
      |> query_from()

    assert query["state"] == "xyz"

    token =
      build_conn()
      |> post("/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => query["code"],
        "redirect_uri" => @redirect_uri,
        "client_id" => client.id,
        "code_verifier" => @verifier
      })
      |> json_response(200)

    assert {:ok, found, _} = Accounts.fetch_user_by_mcp_token(token["access_token"])
    assert found.id == user.id

    reused =
      post(build_conn(), "/oauth/token", %{
        "grant_type" => "authorization_code",
        "code" => query["code"],
        "client_id" => client.id,
        "code_verifier" => @verifier
      })

    assert %{"error" => "invalid_grant"} = json_response(reused, 400)
  end

  test "denying returns access_denied", %{conn: conn} do
    client = register_client()
    conn = log_in_user(conn, user_fixture())

    query =
      conn
      |> post("/oauth/authorize", Map.put(authorize_params(client), "decision", "deny"))
      |> query_from()

    assert query["error"] == "access_denied"
  end

  test "the MCP endpoint refuses a request without token", %{conn: conn} do
    conn = post(conn, "/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
    assert conn.status == 401
  end
end
