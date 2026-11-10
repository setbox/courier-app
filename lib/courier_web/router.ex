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

  pipeline :api_client do
    plug :accepts, ["json"]
    plug CourierWeb.Plugs.ClientAuth
  end

  scope "/api/v1", CourierWeb.Api do
    pipe_through :api_client

    post "/emails", EmailController, :create
    get "/emails", EmailController, :index
    get "/emails/:id", EmailController, :show
    get "/emails/:email_id/events", EmailController, :events
  end

  scope "/webhooks", CourierWeb do
    pipe_through :api

    post "/postmark/:environment_id", PostmarkWebhookController, :create
  end

  scope "/", CourierWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{CourierWeb.UserAuth, :require_authenticated}] do
      live "/", AppLive.Index
      live "/apps/new", AppLive.Form, :new
      live "/apps/:id", AppLive.Show
      live "/apps/:id/edit", AppLive.Form, :edit
      live "/apps/:app_id/environments/new", EnvironmentLive.Form, :new
      live "/apps/:app_id/environments/:id", EnvironmentLive.Show
      live "/apps/:app_id/environments/:id/edit", EnvironmentLive.Form, :edit
      live "/apps/:app_id/environments/:id/email", EnvironmentLive.EmailConfig
      live "/apps/:app_id/environments/:id/recipients", EnvironmentLive.Recipients
      live "/apps/:app_id/environments/:id/webhook", EnvironmentLive.Webhook
      live "/emails", EmailLive.Index
      live "/emails/:id", EmailLive.Show
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
