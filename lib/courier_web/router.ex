defmodule CourierWeb.Router do
  use CourierWeb, :router

  import CourierWeb.UserAuth
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CourierWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CourierWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{CourierWeb.UserAuth, :require_authenticated}] do
      live "/", HomeLive
      live "/settings", UserLive.Settings, :edit
      live "/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/settings/password", UserSessionController, :update_password
  end

  scope "/" do
    pipe_through [:browser, :require_authenticated_user]

    oban_dashboard("/oban")
  end

  scope "/", CourierWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{CourierWeb.UserAuth, :mount_current_scope}] do
      live "/register", UserLive.Registration, :new
      live "/reset-password", UserLive.ForgotPassword, :new
      live "/reset-password/:token", UserLive.ResetPassword, :edit
      live "/confirm", UserLive.Confirmation, :new
      live "/confirm/:token", UserLive.Confirmation, :edit
    end

    post "/confirm", UserSessionController, :confirm
  end

  scope "/", CourierWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{CourierWeb.UserAuth, :mount_current_scope}] do
      live "/login", UserLive.Login, :new
    end

    post "/login", UserSessionController, :create
    delete "/logout", UserSessionController, :delete
  end

  scope "/auth", CourierWeb do
    pipe_through [:browser]

    get "/google", OAuthController, :request
    get "/google/callback", OAuthController, :callback
  end

  if Application.compile_env(:courier, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CourierWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
