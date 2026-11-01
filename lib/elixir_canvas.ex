defmodule ElixirCanvas do
  @moduledoc """
  A local-file-first spatial thinking canvas built with Elixir, Phoenix LiveView,
  and Hakushi.

  Version-1 JSON files on disk are the canonical documents rather than database
  exports. `ElixirCanvas.Document` owns schema validation, unknown-metadata
  retention, and optimistic file persistence; `ElixirCanvasWeb.CanvasLive`
  coordinates the interactive workspace across server files, browser File System
  Access handles, and downloaded copies.
  """
end
