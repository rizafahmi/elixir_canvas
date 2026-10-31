defmodule ElixirCanvasWeb.CanvasLive do
  use ElixirCanvasWeb, :live_view

  import Hakushi.Components
  alias ElixirCanvas.Document
  alias ElixirCanvasWeb.DrawingShapes

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
        drawing_font: "sans",
        dirty: false,
        disk_status: :unchanged,
        error: nil,
        notice: nil,
        generation: 0,
        file_menu_open: false,
        style_open: false
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
        {:error, reason} -> {:noreply, assign(socket, error: reason)}
      end
    end
  end

  def handle_event("save", _params, %{assigns: %{document: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    document = with_drawing_font(socket.assigns.document, socket.assigns.drawing_font)

    case Document.save(document, socket.assigns.graph) do
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

  def handle_event("appearance", %{"font" => font}, socket)
      when font in ["sans", "heading", "mono", "handwritten"] do
    if socket.assigns.document do
      dirty =
        font != Document.drawing_font(socket.assigns.document) or
          socket.assigns.graph != socket.assigns.document.graph

      {:noreply, assign(socket, drawing_font: font, dirty: dirty, notice: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle-file-menu", _params, socket),
    do:
      {:noreply,
       assign(socket, file_menu_open: !socket.assigns.file_menu_open, style_open: false)}

  def handle_event("close-file-menu", _params, socket),
    do: {:noreply, assign(socket, :file_menu_open, false)}

  def handle_event("toggle-style", _params, socket),
    do: {:noreply, assign(socket, style_open: !socket.assigns.style_open, file_menu_open: false)}

  def handle_event("close-overlays", _params, socket),
    do: {:noreply, assign(socket, file_menu_open: false, style_open: false)}

  def handle_event("dismiss-error", _params, socket),
    do: {:noreply, assign(socket, :error, nil)}

  @impl true
  def handle_info({:canvas_changed, graph}, socket) do
    dirty =
      graph != socket.assigns.document.graph or
        socket.assigns.drawing_font != Document.drawing_font(socket.assigns.document)

    {:noreply, assign(socket, graph: graph, dirty: dirty, notice: nil)}
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
      {:ok, document} ->
        put_document(socket, document)

      {:error, reason} ->
        assign(socket, error: reason, path_input: path, file_menu_open: true, notice: nil)
    end
  end

  defp put_document(socket, document) do
    assign(socket,
      document: document,
      graph: document.graph,
      path_input: document.path,
      drawing_font: Document.drawing_font(document),
      dirty: false,
      disk_status: :unchanged,
      error: nil,
      notice: nil,
      file_menu_open: false,
      style_open: false,
      generation: socket.assigns.generation + 1
    )
  end

  defp with_drawing_font(document, font) do
    if Document.drawing_font(document) == font do
      document
    else
      appearance = document.source |> Map.get("appearance", %{}) |> Map.put("font", font)
      %{document | source: Map.put(document.source, "appearance", appearance)}
    end
  end

  defp status_text(document, dirty, disk_status, notice) do
    cond do
      disk_status == :changed -> "Changed on disk"
      disk_status == :unavailable -> "File unavailable"
      dirty -> "Unsaved changes"
      notice -> notice
      document -> "Saved locally"
      true -> "No file open"
    end
  end

  attr :name, :string, required: true
  attr :class, :string, default: ""

  defp glyph(assigns) do
    paths = %{
      "file" => "M5 3H14L19 8V21H5V3ZM13 3V9H19M8 13H15M8 17H13",
      "chevron" => "M8 10L12 14L16 10",
      "save" => "M4 3H17L21 7V21H3V3H4ZM7 3V9H16V3M7 21V14H17V21",
      "style" => "M4 7H20M4 17H20M9 4V10M15 14V20",
      "close" => "M6 6L18 18M18 6L6 18"
    }

    assigns = assign(assigns, :path, Map.fetch!(paths, assigns.name))

    ~H"""
    <svg class={@class} width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d={@path}
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="workspace"
      class="canvas-workspace"
      phx-hook="Workspace"
      data-dirty={to_string(@dirty)}
      data-drawing-font={@drawing_font}
      data-style-open={to_string(@style_open)}
      data-font-state="loading"
    >
      <section :if={@document} class="canvas-area" aria-label="Canvas workspace">
        <.canvas
          id={"board-#{@generation}"}
          graph={@graph}
          kits={[DrawingShapes]}
          on_change={&accept_change/2}
          background={:none}
          papers={true}
          minimap={false}
          export={true}
          fit={true}
          label="Spatial thinking canvas"
          class="drawing-board"
        />
      </section>

      <header class="canvas-header">
        <div class="document-identity">
          <button
            id="file-menu-toggle"
            class="document-toggle"
            phx-click="toggle-file-menu"
            aria-label="Document menu"
            aria-expanded={to_string(@file_menu_open)}
            aria-controls="file-menu"
          >
            <.glyph name="file" />
            <span class="document-name">
              {if @document, do: Path.basename(@document.path), else: "Open a canvas"}
            </span>
            <.glyph name="chevron" />
          </button>
          <span
            id="save-status"
            class={["document-status", @dirty && "unsaved", @disk_status != :unchanged && "conflict"]}
            role="status"
          >
            <span class="status-dot"></span>
            {status_text(@document, @dirty, @disk_status, @notice)}
          </span>
        </div>
        <div class="canvas-actions">
          <button
            id="save-file"
            class="save-button"
            phx-click={JS.dispatch("canvas:save", to: "#workspace")}
            disabled={!@document}
            title="Save (⌘S / Ctrl+S)"
          >
            <.glyph name="save" /><span>Save</span>
          </button>
        </div>
      </header>

      <div :if={@document} class="drawing-dock" role="group" aria-label="Drawing appearance">
        <button
          id="style-toggle"
          class="style-button"
          phx-click="toggle-style"
          aria-label="Object styles"
          aria-pressed={to_string(@style_open)}
        >
          <.glyph name="style" /><span>Style</span>
        </button>
      </div>

      <section
        :if={@file_menu_open}
        id="file-menu"
        class="file-menu"
        aria-label="Local document"
        phx-click-away="close-file-menu"
      >
        <h2 class="menu-heading">Your canvas, your file.</h2>
        <p :if={@document} class="file-location" title={@document.path}>{@document.path}</p>
        <div class="menu-section">
          <form id="open-file-form" class="file-form" phx-submit="open">
            <label class="field-label" for="file-path">Open a local JSON file</label>
            <div class="file-input-row">
              <input
                id="file-path"
                name="path"
                value={@path_input}
                autocomplete="off"
                spellcheck="false"
                required
              />
              <button type="submit" class="menu-button">Open</button>
            </div>
          </form>
          <form id="create-file-form" class="file-form" phx-submit="create">
            <label class="field-label" for="new-file-path">Create a new canvas</label>
            <div class="file-input-row">
              <input
                id="new-file-path"
                name="path"
                placeholder="/path/to/ideas.json"
                autocomplete="off"
                spellcheck="false"
                required
              />
              <button type="submit" class="menu-button">Create</button>
            </div>
          </form>
        </div>
        <div :if={@document} class="menu-section">
          <form id="appearance-form" phx-change="appearance">
            <label class="field-label" for="drawing-font">Drawing lettering</label>
            <select id="drawing-font" name="font">
              <option value="sans" selected={@drawing_font == "sans"}>Body · Sans-serif</option>
              <option value="heading" selected={@drawing_font == "heading"}>Heading</option>
              <option value="mono" selected={@drawing_font == "mono"}>Monospace</option>
              <option value="handwritten" selected={@drawing_font == "handwritten"}>
                Handwritten
              </option>
            </select>
            <p class="menu-footnote">Applies to all text in this file. Save to keep the choice.</p>
          </form>
          <button
            id="reload-file"
            class="menu-button reload-button"
            phx-click="reload"
            data-confirm={@dirty && "Discard unsaved canvas edits and reload the file from disk?"}
          >
            Reload from disk
          </button>
        </div>
        <dl class="shortcut-list">
          <div>
            <dt>Save</dt>
            <dd>⌘ / Ctrl S</dd>
          </div>
          <div>
            <dt>Zoom in</dt>
            <dd>⌘ / Ctrl +</dd>
          </div>
          <div>
            <dt>Zoom out</dt>
            <dd>⌘ / Ctrl −</dd>
          </div>
          <div>
            <dt>Text · rectangle · ellipse</dt>
            <dd>T · R · O</dd>
          </div>
          <div>
            <dt>Arrow · select</dt>
            <dd>A · V</dd>
          </div>
          <div>
            <dt>Pan</dt>
            <dd>Space + drag</dd>
          </div>
        </dl>
        <p class="menu-footnote">Local JSON. No account, no hidden database.</p>
      </section>

      <div class="canvas-messages">
        <div :if={@error} id="file-error" class="canvas-message error" role="alert">
          <span>{@error}</span>
          <button class="message-dismiss" phx-click="dismiss-error" aria-label="Dismiss error">
            <.glyph name="close" />
          </button>
        </div>
        <div
          :if={@disk_status != :unchanged}
          id="disk-warning"
          class="canvas-message warning"
          role="status"
        >
          <span>
            {if @disk_status == :changed,
              do: "The source changed outside the app. Reload before saving.",
              else:
                "The source file is missing or unreadable. Your canvas is still here; saving is blocked."}
          </span>
          <button
            class="message-action"
            phx-click="reload"
            data-confirm={@dirty && "Discard unsaved canvas edits and reload the file from disk?"}
          >
            Reload file
          </button>
        </div>
      </div>

      <section :if={!@document} class="empty-state">
        <.glyph name="file" class="empty-mark" />
        <h1 class="headline-two-tone">Make room <span class="muted">for an idea.</span></h1>
        <p>Open a canvas or create a local file to begin.</p>
        <button class="menu-button" phx-click="toggle-file-menu">Choose a file</button>
      </section>
      <div class="style-hint" role="status">Select an object to change its style.</div>
      <p :if={@document} class="font-message" role="status">Loading drawing fonts…</p>
      <p :if={@document} class="font-error" role="alert">
        The local drawing fonts could not load. Reload the page to try again.
      </p>
      <p class="connection-warning" role="status">
        Connection lost. Keep this tab open; unsaved edits may be lost if the session restarts.
      </p>
    </main>
    """
  end
end
