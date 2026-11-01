defmodule ElixirCanvasWeb.CanvasLive do
  @moduledoc """
  LiveView workspace for editing local version-1 JSON canvases.

  Coordinates Hakushi graph operations, portable drawing typography and color
  roles, dirty/conflict tracking, and persistence across server file paths,
  browser File System Access handles, and copy-download fallbacks.
  """
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
        edit_version: 0,
        pending_save: nil,
        file_menu_open: false,
        style_open: false
      )

    {:ok, load_document(socket, path)}
  end

  @impl true
  def handle_event("open", %{"path" => path}, socket) do
    cond do
      socket.assigns.pending_save ->
        {:noreply, assign(socket, error: "Wait for the current file save to finish.")}

      socket.assigns.dirty ->
        {:noreply,
         assign(socket, error: "Save or reload this canvas before opening another file.")}

      true ->
        {:noreply, load_document(socket, path)}
    end
  end

  def handle_event("create", %{"path" => path}, socket) do
    cond do
      socket.assigns.pending_save ->
        {:noreply, assign(socket, error: "Wait for the current file save to finish.")}

      socket.assigns.dirty ->
        {:noreply,
         assign(socket, error: "Save or reload this canvas before creating another file.")}

      true ->
        case Document.create(path) do
          {:ok, document} -> {:noreply, put_document(socket, document)}
          {:error, reason} -> {:noreply, assign(socket, error: reason)}
        end
    end
  end

  def handle_event("selected-open", params, socket) do
    cond do
      params["generation"] != socket.assigns.generation ->
        {:reply, %{ok: false}, socket}

      socket.assigns.pending_save ->
        {:reply, %{ok: false}, assign(socket, error: "Wait for the current file save to finish.")}

      socket.assigns.dirty ->
        {:reply, %{ok: false},
         assign(socket, error: "Save or reload this canvas before opening another file.")}

      true ->
        load_selected(socket, params)
    end
  end

  def handle_event("selected-reload", params, socket) do
    document = socket.assigns.document

    cond do
      !document || document.persistence == :server_file ||
        params["generation"] != socket.assigns.generation ||
          params["filename"] != document.filename ->
        {:reply, %{ok: false}, socket}

      socket.assigns.pending_save ->
        {:reply, %{ok: false}, assign(socket, error: "Wait for the current file save to finish.")}

      params["edit_version"] != socket.assigns.edit_version ->
        {:reply, %{ok: false},
         assign(socket,
           error:
             "Canvas changed while the file was being read. Reload again to discard those edits."
         )}

      true ->
        load_selected(socket, params)
    end
  end

  def handle_event("save", _params, %{assigns: %{document: nil}} = socket),
    do: {:reply, %{ok: false}, socket}

  def handle_event("save", params, socket) do
    cond do
      socket.assigns.pending_save ->
        {:reply, %{ok: false}, assign(socket, error: "Wait for the current file save to finish.")}

      Map.get(params, "generation", socket.assigns.generation) != socket.assigns.generation ->
        {:reply, %{ok: false}, socket}

      socket.assigns.document.persistence == :server_file ->
        save_server_document(socket)

      params["generation"] == socket.assigns.generation ->
        prepare_selected_save(socket)

      true ->
        {:reply, %{ok: false},
         assign(socket, error: "Use the Save button to save the selected file on this device.")}
    end
  end

  def handle_event("selected-saved", %{"token" => token, "generation" => generation}, socket) do
    case socket.assigns.pending_save do
      %{
        token: ^token,
        generation: ^generation,
        document: %{persistence: :browser_file} = document
      } ->
        dirty =
          socket.assigns.graph != document.graph or
            socket.assigns.drawing_font != Document.drawing_font(document)

        {:reply, %{ok: true},
         assign(socket,
           document: document,
           pending_save: nil,
           dirty: dirty,
           disk_status: :unchanged,
           error: nil,
           notice: if(dirty, do: nil, else: "Saved to disk")
         )}

      _ ->
        {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "selected-copy-downloaded",
        %{"token" => token, "generation" => generation},
        socket
      ) do
    case socket.assigns.pending_save do
      %{token: ^token, generation: ^generation, document: %{persistence: :save_copy}} ->
        {:reply, %{ok: true},
         assign(socket,
           pending_save: nil,
           error: nil,
           notice: "Copy downloaded; original file not changed"
         )}

      _ ->
        {:reply, %{ok: false}, socket}
    end
  end

  def handle_event(
        "selected-save-error",
        %{"token" => token, "generation" => generation} = params,
        socket
      ) do
    case socket.assigns.pending_save do
      %{token: ^token, generation: ^generation} ->
        status =
          case params["status"] do
            "changed" -> :changed
            "unavailable" -> :unavailable
            _ -> socket.assigns.disk_status
          end

        {:reply, %{ok: false},
         assign(socket,
           pending_save: nil,
           error: params["message"],
           notice: nil,
           disk_status: status
         )}

      _ ->
        {:reply, %{ok: false}, socket}
    end
  end

  def handle_event("selected-error", %{"generation" => generation, "message" => message}, socket)
      when is_binary(message) do
    if generation == socket.assigns.generation do
      {:noreply, assign(socket, error: message, notice: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reload", _params, %{assigns: %{document: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("reload", _params, socket) do
    cond do
      socket.assigns.pending_save ->
        {:noreply, assign(socket, error: "Wait for the current file save to finish.")}

      socket.assigns.document.persistence == :server_file ->
        {:noreply, load_document(socket, socket.assigns.document.path)}

      true ->
        {:noreply,
         assign(socket, error: "Use Reload to read the selected file again on this device.")}
    end
  end

  def handle_event("appearance", %{"font" => font}, socket)
      when font in ["sans", "heading", "mono", "handwritten"] do
    if socket.assigns.document do
      dirty =
        font != Document.drawing_font(socket.assigns.document) or
          socket.assigns.graph != socket.assigns.document.graph

      {:noreply,
       assign(socket,
         drawing_font: font,
         dirty: dirty,
         notice: nil,
         edit_version:
           socket.assigns.edit_version + if(font != socket.assigns.drawing_font, do: 1, else: 0)
       )}
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

    {:noreply,
     assign(socket,
       graph: graph,
       dirty: dirty,
       notice: nil,
       edit_version:
         socket.assigns.edit_version + if(graph != socket.assigns.graph, do: 1, else: 0)
     )}
  end

  def handle_info(:check_file, socket) do
    Process.send_after(self(), :check_file, 1_000)

    status =
      case socket.assigns.document do
        %{persistence: :server_file} = document -> Document.status(document)
        _ -> socket.assigns.disk_status
      end

    {:noreply, assign(socket, :disk_status, status)}
  end

  defp accept_change(change, %{result: graph}) do
    invalid =
      change.op in [:add, :connect, :reconnect] and
        Enum.any?(change.edges, fn changed ->
          edge = Map.get(graph.edges, changed.id)
          edge && edge.source == edge.target && edge.source_handle == edge.target_handle
        end)

    if invalid do
      {:error, "Choose a different connection handle on this item."}
    else
      send(self(), {:canvas_changed, graph})
      :ok
    end
  end

  defp load_selected(socket, %{"mode" => mode, "filename" => filename, "bytes" => bytes})
       when mode in ["browser_file", "save_copy"] and is_binary(filename) and filename != "" and
              is_binary(bytes) do
    persistence = if mode == "browser_file", do: :browser_file, else: :save_copy

    case Document.open_selected(filename, bytes, persistence) do
      {:ok, document} ->
        socket = put_document(socket, document)

        {:reply,
         %{ok: true, generation: socket.assigns.generation, revision: revision_hex(document)},
         socket}

      {:error, reason} ->
        {:reply, %{ok: false}, assign(socket, error: reason, notice: nil)}
    end
  end

  defp load_selected(socket, _params) do
    {:reply, %{ok: false},
     assign(socket, error: "Choose a canvas JSON file using Open.", notice: nil)}
  end

  defp save_server_document(socket) do
    document = with_drawing_font(socket.assigns.document, socket.assigns.drawing_font)

    case Document.save(document, socket.assigns.graph) do
      {:ok, document} ->
        {:reply, %{ok: true},
         assign(socket,
           document: document,
           dirty: false,
           disk_status: :unchanged,
           error: nil,
           notice: "Saved to disk"
         )}

      {:error, reason} ->
        {:reply, %{ok: false}, assign(socket, error: reason, notice: nil)}
    end
  end

  defp prepare_selected_save(socket) do
    document = with_drawing_font(socket.assigns.document, socket.assigns.drawing_font)

    case Document.prepare_save(document, socket.assigns.graph) do
      {:ok, bytes, pending_document} ->
        token = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        generation = socket.assigns.generation
        pending = %{token: token, generation: generation, document: pending_document}

        {:reply,
         %{
           ok: true,
           token: token,
           generation: generation,
           bytes: bytes,
           revision: revision_hex(socket.assigns.document),
           saved_revision: revision_hex(pending_document),
           mode: Atom.to_string(document.persistence),
           filename: document.filename
         }, assign(socket, pending_save: pending, error: nil, notice: nil)}

      {:error, reason} ->
        {:reply, %{ok: false}, assign(socket, error: reason, notice: nil)}
    end
  end

  defp revision_hex(document), do: Base.encode16(document.revision, case: :lower)

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
      page_title: document.filename,
      document: document,
      graph: document.graph,
      path_input: document.path || socket.assigns.path_input,
      drawing_font: Document.drawing_font(document),
      dirty: false,
      disk_status: :unchanged,
      error: nil,
      notice: nil,
      file_menu_open: false,
      style_open: false,
      generation: socket.assigns.generation + 1,
      edit_version: socket.assigns.edit_version + 1,
      pending_save: nil
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
      document && document.persistence == :save_copy -> "Opened copy"
      document && document.persistence == :browser_file -> "Selected file open"
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
      data-file-mode={if @document, do: Atom.to_string(@document.persistence), else: "none"}
      data-file-name={if @document, do: @document.filename, else: ""}
      data-generation={@generation}
      data-edit-version={@edit_version}
      data-file-busy={to_string(@pending_save != nil)}
      data-style-open={to_string(@style_open)}
      data-font-state="loading"
    >
      <input
        id="canvas-file-input"
        class="sr-only"
        type="file"
        accept=".json,application/json"
        aria-label="Canvas JSON file"
        tabindex="-1"
        phx-update="ignore"
      />
      <p :if={@document && @document.persistence == :save_copy} id="save-copy-help" class="sr-only">
        Downloads a JSON copy. The original file is not changed, and unsaved changes remain until you reload.
      </p>
      <section :if={@document} class="canvas-area" aria-label="Canvas workspace">
        <.canvas
          id={"board-#{@generation}"}
          graph={@graph}
          kits={[DrawingShapes]}
          rules={[loops: true]}
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
              {if @document, do: @document.filename, else: "Open a canvas"}
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
            disabled={!@document || @pending_save != nil}
            title={
              if @document && @document.persistence == :save_copy,
                do: "Download a copy (⌘S / Ctrl+S); the original file is not changed",
                else: "Save (⌘S / Ctrl+S)"
            }
            aria-describedby={@document && @document.persistence == :save_copy && "save-copy-help"}
          >
            <.glyph name="save" />
            <span>
              {if @document && @document.persistence == :save_copy, do: "Save copy", else: "Save"}
            </span>
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
        <p :if={@document && @document.path} class="file-location" title={@document.path}>
          {@document.path}
        </p>
        <p :if={@document && !@document.path} id="selected-file-help" class="menu-footnote">
          {if @document.persistence == :browser_file,
            do: "Selected on this device. Save writes this file; Reload reads it again.",
            else:
              "Opened as a copy. Save copy downloads JSON; it cannot overwrite the original. Reload asks you to select this file again."}
        </p>
        <div class="menu-section">
          <button
            id="open-native-file"
            type="button"
            class="menu-button native-open-button"
            phx-click={JS.dispatch("canvas:open", to: "#workspace")}
            disabled={@pending_save != nil}
            aria-describedby="native-open-help"
          >
            <.glyph name="file" />Open…
          </button>
          <p id="native-open-help" class="menu-footnote" data-native-open-help>
            Choose a canvas JSON file. Supported browsers can save back with your permission; other browsers download a copy.
          </p>
        </div>
        <details id="server-file-options" class="menu-section server-file-options">
          <summary>Advanced: server file path</summary>
          <p class="menu-footnote">For files on the computer running this app.</p>
          <form id="open-file-form" class="file-form" phx-submit="open">
            <label class="field-label" for="file-path">Open a server JSON file</label>
            <div class="file-input-row">
              <input
                id="file-path"
                name="path"
                value={@path_input}
                autocomplete="off"
                spellcheck="false"
                required
              />
              <button type="submit" class="menu-button" disabled={@pending_save != nil}>
                Open path
              </button>
            </div>
          </form>
          <form id="create-file-form" class="file-form" phx-submit="create">
            <label class="field-label" for="new-file-path">Create a server canvas</label>
            <div class="file-input-row">
              <input
                id="new-file-path"
                name="path"
                placeholder="/path/to/ideas.json"
                autocomplete="off"
                spellcheck="false"
                required
              />
              <button type="submit" class="menu-button" disabled={@pending_save != nil}>
                Create
              </button>
            </div>
          </form>
        </details>
        <div :if={@document} class="menu-section">
          <form id="appearance-form" phx-change="appearance">
            <label class="field-label" for="drawing-font">Default text style</label>
            <select id="drawing-font" name="font" aria-describedby="drawing-font-help">
              <option value="sans" selected={@drawing_font == "sans"}>Normal</option>
              <option value="heading" selected={@drawing_font == "heading"}>Title</option>
              <option value="mono" selected={@drawing_font == "mono"}>Code</option>
              <option value="handwritten" selected={@drawing_font == "handwritten"}>
                Handwritten
              </option>
            </select>
            <p id="drawing-font-help" class="menu-footnote">
              Used by text without its own style. Save to keep it.
            </p>
          </form>
          <button
            id="reload-file"
            class="menu-button reload-button"
            phx-click={
              if @document.persistence == :server_file,
                do: "reload",
                else: JS.dispatch("canvas:reload", to: "#workspace")
            }
            disabled={@pending_save != nil}
            data-confirm={
              @document.persistence == :server_file && @dirty &&
                "Discard unsaved canvas edits and reload the file from disk?"
            }
          >
            {if @document.persistence == :save_copy,
              do: "Reload: choose file again…",
              else: "Reload from disk"}
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
            <dt>Line · arrow · select</dt>
            <dd>L · A · V</dd>
          </div>
          <div>
            <dt>Line direction · 45°</dt>
            <dd>Shift + drag</dd>
          </div>
          <div>
            <dt>Pan</dt>
            <dd>Space + drag</dd>
          </div>
        </dl>
        <p class="menu-footnote">Local JSON. No account, no hidden database.</p>
      </section>

      <div class="canvas-messages">
        <div
          :if={@notice && @document && @document.persistence == :save_copy}
          id="file-notice"
          class="canvas-message warning"
          role="status"
        >
          <span>{@notice}</span>
        </div>
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
            phx-click={
              if @document.persistence == :server_file,
                do: "reload",
                else: JS.dispatch("canvas:reload", to: "#workspace")
            }
            disabled={@pending_save != nil}
            data-confirm={
              @document.persistence == :server_file && @dirty &&
                "Discard unsaved canvas edits and reload the file from disk?"
            }
          >
            Reload file
          </button>
        </div>
      </div>

      <section :if={!@document} class="empty-state">
        <.glyph name="file" class="empty-mark" />
        <h1 class="headline-two-tone">Make room <span class="muted">for an idea.</span></h1>
        <p>Open a canvas or create a local file to begin.</p>
        <button
          id="empty-open-file"
          type="button"
          class="menu-button"
          phx-click={JS.dispatch("canvas:open", to: "#workspace")}
          aria-describedby="empty-native-open-help"
        >
          Open a canvas…
        </button>
        <p id="empty-native-open-help" data-native-open-help>
          Supported browsers can save back with your permission; other browsers download a copy.
        </p>
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
