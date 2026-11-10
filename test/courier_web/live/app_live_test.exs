defmodule CourierWeb.AppLiveTest do
  use CourierWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Courier.MessagingFixtures

  alias Courier.Core.Apps

  setup :register_and_log_in_user

  test "requires login" do
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), ~p"/")
  end

  test "the list has no form, only the link to the new app page", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/")

    refute html =~ "<form"

    assert {:ok, _lv, html} =
             lv
             |> element("a", "Nova aplicação")
             |> render_click()
             |> follow_redirect(conn, ~p"/apps/new")

    assert html =~ "app_form"
  end

  test "creates an app in its own page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/apps/new")

    html = lv |> form("#app_form", app: %{name: ""}) |> render_change()
    assert html =~ "não pode ficar em branco"

    {:ok, _lv, html} =
      lv
      |> form("#app_form", app: %{name: "Jayio"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Jayio"
    assert html =~ "Novo ambiente"
    refute html =~ "<form"
  end

  test "renames an app", %{conn: conn} do
    app = app_fixture(name: "Antigo")
    {:ok, lv, _html} = live(conn, ~p"/apps/#{app}/edit")

    {:ok, _lv, html} =
      lv
      |> form("#app_form", app: %{name: "Novo nome"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/apps/#{app}")

    assert html =~ "Novo nome"
    assert Apps.get_app!(app.id).slug == app.slug
  end

  test "creates an environment in its own page", %{conn: conn} do
    app = app_fixture()
    {:ok, lv, _html} = live(conn, ~p"/apps/#{app}/environments/new")

    {:ok, _lv, html} =
      lv
      |> form("#environment_form", environment: %{name: "prod"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "Nenhum token gerado"
    refute html =~ "<form"
  end

  test "lists apps with their environments", %{conn: conn} do
    environment = environment_fixture(name: "stage")
    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ environment.app.name
    assert html =~ "stage"
  end
end
