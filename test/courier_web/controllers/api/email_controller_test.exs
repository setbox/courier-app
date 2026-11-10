defmodule CourierWeb.Api.EmailControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.MessagingFixtures

  alias Courier.Core.StorageStub

  setup %{conn: conn} do
    {environment, token} = configured_environment_fixture()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("api-key", token)

    %{conn: conn, environment: environment}
  end

  describe "auth" do
    test "rejects a missing or wrong key" do
      conn = build_conn() |> post(~p"/api/v1/emails", email_params())
      assert %{"error" => %{"code" => "invalid_api_key"}} = json_response(conn, 401)

      conn = build_conn() |> put_req_header("api-key", "cl_wrong") |> get(~p"/api/v1/emails")
      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/emails" do
    test "accepts with 202", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/emails", email_params())

      assert %{"id" => id, "status" => "queued"} = json_response(conn, 202)
      assert get_resp_header(conn, "idempotent-replayed") == ["false"]
      assert is_binary(id)
    end

    test "replays with the same Idempotency-Key", %{conn: conn} do
      first =
        conn
        |> put_req_header("idempotency-key", "abc")
        |> post(~p"/api/v1/emails", email_params())

      again =
        conn
        |> put_req_header("idempotency-key", "abc")
        |> post(~p"/api/v1/emails", email_params())

      assert json_response(again, 202)["id"] == json_response(first, 202)["id"]
      assert get_resp_header(again, "idempotent-replayed") == ["true"]
    end

    test "answers 422 with field errors", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/emails", %{"to" => ["x"]})

      assert %{"error" => %{"code" => "invalid_request", "details" => details}} =
               json_response(conn, 422)

      assert details["to"] == ["invalid address: x"]
      assert details["subject"]
    end

    test "answers provider_not_configured", %{conn: conn} do
      environment = environment_fixture()
      {:ok, _env, token} = Courier.Core.Apps.regenerate_client_token(environment)

      conn = conn |> put_req_header("api-key", token) |> post(~p"/api/v1/emails", email_params())
      assert %{"error" => %{"code" => "provider_not_configured"}} = json_response(conn, 422)
    end

    test "answers recipient_not_allowed with the blocked addresses", %{
      conn: conn,
      environment: environment
    } do
      {:ok, _} =
        Courier.Core.Apps.update_recipient_lists(environment, %{
          "blocked_recipients" => "ana@exemplo.com.br"
        })

      conn = post(conn, ~p"/api/v1/emails", email_params())

      assert %{
               "error" => %{
                 "code" => "recipient_not_allowed",
                 "details" => %{"recipients" => ["ana@exemplo.com.br"]}
               }
             } =
               json_response(conn, 422)
    end

    test "answers 503 when the storage fails", %{conn: conn} do
      StorageStub.fail_next_puts()
      conn = post(conn, ~p"/api/v1/emails", email_params())
      assert %{"error" => %{"code" => "storage_unavailable"}} = json_response(conn, 503)
    end
  end

  describe "queries" do
    setup %{environment: environment} do
      email = email_fixture(environment, %{"metadata" => %{"order_id" => "9"}})
      %{email: email}
    end

    test "shows an email with recipients", %{conn: conn, email: email} do
      body = conn |> get(~p"/api/v1/emails/#{email.id}") |> json_response(200)

      assert body["id"] == email.id
      assert body["status"] == "queued"

      assert [%{"address" => "ana@exemplo.com.br", "kind" => "to", "status" => "pending"}] =
               body["recipients"]
    end

    test "does not show an email of another environment", %{conn: conn} do
      {other, _} = configured_environment_fixture()
      foreign = email_fixture(other)

      assert %{"error" => %{"code" => "not_found"}} =
               conn |> get(~p"/api/v1/emails/#{foreign.id}") |> json_response(404)

      assert conn |> get(~p"/api/v1/emails/not-a-uuid") |> json_response(404)
    end

    test "lists with filters", %{conn: conn, email: email, environment: environment} do
      _other = email_fixture(environment)

      body = conn |> get(~p"/api/v1/emails?#{[metadata: %{order_id: "9"}]}") |> json_response(200)
      assert [%{"id" => id}] = body["data"]
      assert id == email.id
      assert body["next_cursor"] == nil

      body = conn |> get(~p"/api/v1/emails?#{[limit: 1]}") |> json_response(200)
      assert length(body["data"]) == 1
      assert body["next_cursor"]
    end

    test "lists the events", %{conn: conn, email: email} do
      body = conn |> get(~p"/api/v1/emails/#{email.id}/events") |> json_response(200)
      assert [%{"type" => "queued"}] = body["data"]
    end
  end
end
