defmodule CourierWeb.UnsubscribeControllerTest do
  use CourierWeb.ConnCase, async: true

  import Courier.MessagingFixtures

  alias Courier.Core.Unsubscribes

  setup do
    {environment, _token} = configured_environment_fixture()
    email = email_fixture(environment, %{"category" => "marketing"})
    token = email |> Unsubscribes.url("ana@exemplo.com.br") |> String.split("/u/") |> List.last()
    %{environment: environment, token: token}
  end

  test "shows a confirmation page without unsubscribing", %{
    conn: conn,
    environment: environment,
    token: token
  } do
    conn = get(conn, ~p"/u/#{token}")

    assert html_response(conn, 200) =~ "Cancelar inscrição"
    assert Unsubscribes.count(environment) == 0
  end

  test "unsubscribes on POST, including one-click without CSRF token", %{
    conn: conn,
    environment: environment,
    token: token
  } do
    conn = post(conn, ~p"/u/#{token}", %{"List-Unsubscribe" => "One-Click"})

    assert html_response(conn, 200) =~ "Inscrição cancelada"
    assert Unsubscribes.count(environment) == 1
  end

  test "refuses a forged token", %{conn: conn} do
    assert conn |> get(~p"/u/forged") |> html_response(404) =~ "Link inválido"
    assert build_conn() |> post(~p"/u/forged") |> html_response(404) =~ "Link inválido"
  end
end
