defmodule ElixirCanvasWeb.Router do
  use ElixirCanvasWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ElixirCanvasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ElixirCanvasWeb do
    pipe_through :browser

    live "/", CanvasLive
  end
end
