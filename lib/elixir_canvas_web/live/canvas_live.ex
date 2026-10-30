defmodule ElixirCanvasWeb.CanvasLive do
  use ElixirCanvasWeb, :live_view

  import Hakushi.Components
  alias ElixirCanvas.Document

  @impl true
  def mount(_params, _session, socket) do
    path = System.get_env("CANVAS_FILE") || Path.expand("examples/welcome.json")
    if connected?(socket), do: Process.send_after(self(), :check_file, 1_000)

    socket =
      assign(socket,
        page_title: "Canvas",
        document: nil,
        graph: nil,
        path_input: path,
        dirty: false,
        disk_status: :unchanged,
        error: nil,
        notice: nil,
        generation: 0
      )

    {:ok, load_document(socket, path)}
  end

  @impl true
  def handle_event("open", %{"path" => path}, socket) do
    if socket.assigns.dirty do
      {:noreply, assign(socket, error: "Save or reload this canvas before opening another file.")}
    else
      {:noreply, load_document(socket, path)}
    end
  end

  def handle_event("create", %{"path" => path}, socket) do
    if socket.assigns.dirty do
      {:noreply,
       assign(socket, error: "Save or reload this canvas before creating another file.")}
    else
      case Document.create(path) do
        {:ok, document} -> {:noreply, put_document(socket, document)}
        {:error, reason} -> {:noreply, assign(socket, error: reason, path_input: path)}
      end
    end
  end

  def handle_event("save", _params, %{assigns: %{document: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    case Document.save(socket.assigns.document, socket.assigns.graph) do
      {:ok, document} ->
        {:noreply,
         assign(socket,
           document: document,
           dirty: false,
           disk_status: :unchanged,
           error: nil,
           notice: "Saved to disk"
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: reason, notice: nil)}
    end
  end

  def handle_event("reload", _params, %{assigns: %{document: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("reload", _params, socket),
    do: {:noreply, load_document(socket, socket.assigns.document.path)}

  @impl true
  def handle_info({:canvas_changed, graph}, socket) do
    {:noreply,
     assign(socket,
       graph: graph,
       dirty: graph != socket.assigns.document.graph,
       notice: nil
     )}
  end

  def handle_info(:check_file, socket) do
    Process.send_after(self(), :check_file, 1_000)

    status =
      if socket.assigns.document, do: Document.status(socket.assigns.document), else: :unchanged

    {:noreply, assign(socket, :disk_status, status)}
  end

  defp accept_change(_change, %{result: graph}) do
    send(self(), {:canvas_changed, graph})
    :ok
  end

  defp load_document(socket, path) do
    case Document.open(path) do
      {:ok, document} -> put_document(socket, document)
      {:error, reason} -> assign(socket, error: reason, path_input: path, notice: nil)
    end
  end

  defp put_document(socket, document) do
    assign(socket,
      document: document,
      graph: document.graph,
      path_input: document.path,
      dirty: false,
      disk_status: :unchanged,
      error: nil,
      notice: nil,
      generation: socket.assigns.generation + 1
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main id="workspace" phx-hook="Workspace" data-dirty={to_string(@dirty)}>
      <header class="topbar">
        <a class="wordmark" href="/" aria-label="Canvas home">
          canvas<span class="wordmark-dot">.</span>
        </a>
        <div class="document-heading">
          <strong>{if @document, do: Path.basename(@document.path), else: "Open a canvas"}</strong>
          <span class="document-state" role="status" id="save-status">
            <span class={["status-dot", @dirty && "unsaved"]}></span>
            {cond do
              @disk_status == :changed -> "Changed on disk"
              @disk_status == :unavailable -> "File unavailable"
              @dirty -> "Unsaved changes"
              @notice -> @notice
              @document -> "Saved locally"
              true -> "No document"
            end}
          </span>
        </div>
        <div class="header-actions">
          <span class="local-label">Local file · No account</span>
          <button
            id="reload-file"
            phx-click="reload"
            disabled={!@document}
            data-confirm={@dirty && "Discard unsaved canvas edits and reload the file from disk?"}
          >
            Reload
          </button>
          <button
            id="save-file"
            class="primary"
            phx-click={JS.dispatch("canvas:save", to: "#workspace")}
            disabled={!@document}
            title="Save (⌘S / Ctrl+S)"
          >
            Save <kbd>⌘S</kbd>
          </button>
        </div>
      </header>

      <section class="filebar" aria-label="Local document">
        <span class="file-label">SOURCE FILE</span>
        <form id="open-file-form" phx-submit="open">
          <label class="sr-only" for="file-path">Local JSON file path</label>
          <input
            id="file-path"
            name="path"
            value={@path_input}
            autocomplete="off"
            spellcheck="false"
            required
          />
          <button type="submit">Open</button>
        </form>
        <form id="create-file-form" phx-submit="create">
          <label class="sr-only" for="new-file-path">New JSON file path</label>
          <input
            id="new-file-path"
            name="path"
            placeholder="/path/to/new-canvas.json"
            autocomplete="off"
            spellcheck="false"
            required
          />
          <button type="submit">New file</button>
        </form>
      </section>

      <div :if={@error} id="file-error" class="message error" role="alert">{@error}</div>
      <div :if={@disk_status != :unchanged} id="disk-warning" class="message warning" role="status">
        {if @disk_status == :changed,
          do:
            "This file changed outside the app. Reload to read it; saving will not overwrite the detected revision.",
          else:
            "The source file is missing or unreadable. Your canvas remains open, but saving is blocked."}
      </div>

      <section :if={@document} class="canvas-area" aria-label="Canvas workspace">
        <.canvas
          id={"board-#{@generation}"}
          graph={@graph}
          kits={[Hakushi.Kits.Shapes]}
          on_change={&accept_change/2}
          background={:dots}
          papers={true}
          minimap={false}
          fit={true}
          label="Spatial thinking canvas"
          class="drawing-board"
        />
        <div class="canvas-caption" aria-hidden="true">A little room to think.</div>
      </section>
      <section :if={!@document} class="empty-state">
        <h1>Your ideas, in your files.</h1>
        <p>Open a canvas JSON file above, or choose a path and create a new one.</p>
      </section>

      <footer class="statusbar">
        <span :if={@graph}>
          {map_size(@graph.nodes)} shapes
          <span class="separator">/</span> {map_size(@graph.edges)} connectors
        </span>
        <span :if={!@graph}>File over app</span>
        <span class="interaction-hint">
          R rectangle · O ellipse · T text · A arrow · Double-click to edit · Space + drag to pan
        </span>
        <span>JSON · v1</span>
      </footer>
    </main>
    """
  end
end
