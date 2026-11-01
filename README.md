# Elixir Canvas

A local-file-first spatial thinking canvas built with Elixir, Phoenix LiveView,
and Hakushi. The JSON file is the document, not an export from a database.

## Interface

The editor uses the light Neo-Acid design system: Raw Plaster paper, square-edged
floating controls, crisp black frames, and acid-filled active tools. Hovered tools
stay neutral so the selected tool remains distinct. Cobalt marks object selection
and keyboard focus. Drawing colors and typography resolve through the interface's
theme from portable names; the document retains its authored geometry and style intent.

- **Paper** sits beside the filename at the upper left. The filename opens the
  document menu: native **Open…**, advanced server-path open/create, reload,
  **Default text style**, and shortcut help.
- **Download** exports an image beside **Save** at the upper right. Save writes
  the selected JSON when possible; **Save copy** explicitly downloads a separate
  JSON copy otherwise. Image Download becomes icon-only on narrow screens.
  Their measured widths keep an 8px gap through Save/Save copy changes, font loading,
  and window resizing; the filename yields space without hiding either action.
- Drawing tools and **Style** share the bottom dock, separated by a divider.
  **Line** (`L`) has a plain segment icon; **Arrow** (`A`) keeps its arrow icon.
  The inspector opens above the dock, not over the drawing tools. Style becomes
  icon-only on the smallest screens; all eight tool buttons remain visible at 320px.
- Undo and redo stay at the top of the left rail. The live zoom percentage below
  them opens a popover with zoom out/in, Fit to screen, and Reset to 100%.
  Repeated adjustments keep it open; Escape or an outside click closes it.
  Opening the popover does not change zoom, and the percentage also tracks wheel
  zoom while closed.
- Arrangement remains separate below a divider, with its options beside the
  rail. The rail ends above the dock and scrolls vertically in short windows.
- Selection alone does not open Style. Escape closes the menus and inspector.
- Unsaved state remains visible under the filename. External changes and save
  failures appear as actionable messages rather than disappearing into a menu.

New files use the generic `sans` typography role. **Default text style** selects
the document default: **Normal**, **Title**, **Code**, or **Handwritten**. In
**Style**, the **Text style** group shows the selected shapes’ current style and
lets them choose an explicit style. Save retains generic roles, not font-family names.
The current Neo-Acid renderer resolves them to Mona Sans, Unbounded, Monaspace
Neon, and Amatic SC respectively. A different interface can choose different
families. Text may wrap differently, but opening or changing a typography role
does not resize or reposition authored objects.

The five self-hosted Neo-Acid faces serve the interface and the matching drawing
roles: Unbounded 800, Mona Sans 400/700, and Monaspace Neon 400/700.
Handwritten intent uses the separately bundled Amatic SC 700 face. Fonts are served
from `priv/static/fonts`; canvas initialization waits for the resolved drawing
font before measuring or editing text. No npm install is needed to run the app.

See [DESIGN.md](DESIGN.md) for the shared design rules and the app-specific
light-first adaptation. Shared primitives are in `assets/css/tokens.css`; workspace
styling is in `assets/css/app.css`. The actual editor is the design surface, not a
separate visual-study route.

Amatic SC Bold is an unmodified upstream distribution from
[Google Fonts](https://github.com/google/fonts), with its SIL Open Font License
notice in `priv/static/fonts/amatic-sc/OFL.txt`. The five Neo-Acid faces are
vendored from [Fontsource](https://fontsource.org/) packages `@fontsource/unbounded`,
`@fontsource/mona-sans`, and `@fontsource/monaspace-neon`; their upstream SIL Open
Font License notices are included in `priv/static/fonts/neo-acid`.

## Run

Requires Elixir 1.18+ and a compatible Erlang/OTP, available through Nix. The
application has no database, account service, or npm installation step. Mix
fetches the dependencies and the esbuild binary used to bundle local assets.

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>. The initial document is `examples/welcome.json`.
Saving it edits that actual example file. To start with a different file:

```sh
CANVAS_FILE=/absolute/path/to/ideas.json mix phx.server
```

Use **Open…** in the document menu to choose a JSON canvas with the operating
system's file picker. The selected bytes are validated by the same document
decoder as server files. The browser provides a filename, not an absolute server
path; opening a selected file never redirects Save to the initial document or
guesses a path from its name. Cancelled pickers and invalid content leave the
current document intact. Opening another file is blocked while canvas edits or
pending text commits remain unsaved.

On supporting browsers in a secure context (including localhost), the browser's
File System Access handle lets **Save** write the selected file after permission
is granted, and **Reload from disk** reads that handle again. Handles belong to
the current tab; a page/session restart requires opening the file again. Direct
saving requires the native picker plus file-handle read, write, and permission
methods; the document menu explains the available behavior before opening.
Safari, Firefox, and browsers with missing or incomplete support use a genuine
file-input picker instead. This opens a copy: **Save copy** downloads JSON, shows
“Copy downloaded; original file not changed”, and keeps unsaved edits marked
dirty because the app cannot confirm where you saved the download. **Reload:
choose file again…** asks you to reselect the original file; it does not pretend
an in-memory snapshot is fresh disk content.

Browser automation exercises real file-input selection and downloaded JSON.
Direct-write automation can exercise genuine origin-private file handles, but
does not verify the operating-system picker or its visible permission prompts;
those require a manual check in a supporting browser.

**Advanced: server file path** retains the explicit server-local workflow. Its
source-path field opens existing files on the machine running Phoenix. The
new-file field creates an empty document at a path whose parent directory already
exists and refuses to replace an existing file. Paths can be absolute or relative
to the server's working directory. These are server paths, not browser-selected
file locations.

**Keep the server local.** It intentionally has access to local files, without
accounts or access controls. Development and production configurations bind to
IPv4 loopback. This is not a hosted multi-user application.

## Edit

- Use the canvas toolbar for rectangles, ellipses, diamonds, triangles, and text.
  **Line** (`L`) draws a standalone straight segment without arrowheads, even when
  drawn between shapes. Hold **Shift** while drawing to snap its direction to
  45° increments (horizontal, vertical, or diagonal); release Shift to draw freely.
  **Arrow** (`A`) keeps the existing behavior: it connects shapes when drawn
  between them and creates a standalone arrow elsewhere.
  Dragging between shape handles also creates a connected arrow.
  To loop back to the same shape, drag between two different side handles.
  The connected arrow curves outside the shape and returns to its target handle;
  returning to the same handle does not create an edge.
- Select a standalone line or arrow to drag either endpoint; the opposite endpoint
  stays fixed. Focus an endpoint and use the arrow keys for precise adjustments.
  An endpoint drag is one undoable edit; Escape or a cancelled pointer gesture
  discards its preview. Locked objects have no editable endpoint controls.
- Double-click a text-bearing shape to edit its text. Select it to resize or
  rotate it; the selection outline, resize handles, and rotation knob follow the
  shape while turning and after release. Resize along the shape's rotated axes;
  the opposite corner or side stays fixed. Escape or a cancelled pointer gesture
  discards the rotation or resize preview. Open **Style** to change its appearance.
- Pan with Space + drag; open the left rail's zoom percentage to zoom or fit the canvas.
- With a canvas loaded, Command/Ctrl + `+` (or `=`) zooms in and Command/Ctrl + `-`
  zooms out instead of zooming the browser page. These work with the zoom popover
  closed or open, including while a text field has focus. Unmodified `+` and `-`
  still type normally.
- Undo and redo are provided by Hakushi. Reloading the source resets that history.
- Save explicitly with **Save** or **Save copy**, Command-S, or Control-S. Saving
  commits an active shape text editor and waits for Hakushi's resulting changes,
  including automatic text-box growth. Unsaved changes live in memory, not in a
  database. A browser write acknowledgement only clears edits included in its
  serialized snapshot; edits made while writing remain dirty.
- Edit the JSON in an ordinary text editor, then reload it through the document
  menu. Reload asks before discarding unsaved canvas edits. Browser-selected
  copies must be selected again; handle-backed files and server-path files are
  reread from their respective source.

Server-path files are checked once a second. A detected external modification,
removal, or read failure leaves the current canvas intact. Their saves check the
last-read SHA-256 revision even before the next check. Browser-selected handles
are checked when saving or reloading, not polled by the server. Saving hashes the
current selected file before opening its writer and again before closing it;
changed or unavailable sources refuse the write without discarding canvas edits.
Input-opened copies have no live disk handle, so external changes can only be read
by selecting the file again. Invalid content never replaces the open graph.

Server-path saves write and sync a temporary sibling file, preserve permission
bits, recheck the revision, and rename over the source. App saves to that path are
serialized across tabs. Browser-handle saves use an exclusive writable stream;
the file is replaced only after the stream closes successfully. Both are
optimistic checks, **not a filesystem compare-and-swap or a lock respected by
external editors**: an external write racing the final check and replacement is
not excluded. Take turns editing externally; automatic merging is absent.
Server paths refuse symbolic links. Server saves do not preserve extended
attributes or guarantee parent-directory power-loss durability; browser file
permissions and filesystem write behavior are controlled by the browser.

## Document format: version 1

See `examples/welcome.json` for a hand-written document. Files use UTF-8 JSON with
three required top-level fields: integer `version: 1`, an ordered `nodes` array,
and an `edges` array. This is an app-owned format based on Hakushi 0.7's graph
serialization, not the JSON Canvas standard.

### Drawing appearance

Optional top-level `appearance` is an object. Its `font`, when present, is a
generic typography role, not a font-family name. A missing object or missing
`font` means `sans`; saving an existing file does not insert appearance metadata
unless you explicitly change the default text style.

| Role | Intent | Current Neo-Acid rendering |
| --- | --- | --- |
| `sans` | Body and general labels | Mona Sans 400; large emphasis 700 |
| `heading` | Display headings | Unbounded 800 |
| `mono` | Code and technical labels | Monaspace Neon 400; large emphasis 700 |
| `handwritten` | Handwritten lettering | Amatic SC 700 |

New files explicitly include:

```json
"appearance": {"font": "sans"}
```

The document role is the default for shapes and connector labels. Text-bearing
shapes may save an explicit `data.font` override. Missing `data.font` inherits the
document role; choosing an object style saves an explicit role. Standalone lines
do not have a typography role. Shape dimensions
and `data.size` remain authored geometry and size. Other appearance metadata is
preserved; unsupported role names and non-object appearance values are rejected.

The interface owns resolved font families and palette values. It does not add a
theme identifier, resolved font name, or hex colors when saving. Another renderer
may interpret the same roles differently; pixel-identical rendering is not part
of the portable JSON contract. PNG exports capture the current rendered appearance.

New graphical objects explicitly record unfilled ink styling, a two-pixel stroke,
sharp rectangle corners, and left-aligned text. Existing authored corners and
styles are preserved, not reset to the creation defaults. The defaults below
describe hand-written JSON that omits style fields.

### Nodes

Every node has a non-empty, stable string `id`; a `type`; numeric `x` and `y`;
positive numeric `width` and `height`; and a `data` object. Coordinates are canvas
pixels at 100% zoom, with x increasing right and y increasing down. Array order
is stacking order, back to front. Optional `locked` is boolean, default false.
Groups and non-null `parent` values are not supported.

Supported types:

- `shape`: `data.kind` is `rect`, `ellipse`, `diamond`, `triangle`, or `text`.
  `data.text` is embedded plain text, defaults to an empty string, and is at most
  2,000 Unicode characters, matching Hakushi's editor limit.
- `shape-line`: a standalone line or arrow. `data.from` and `data.to` are `[x, y]`
  endpoint pairs relative to the node's box; horizontal and vertical segments
  still have positive box dimensions. Line-tool creations explicitly save
  `data.arrow: "none"`; existing arrow values remain unchanged by endpoint edits.
  Standalone lines have no text or font role. Connections between objects belong
  in `edges`.

Style fields in `data` follow the Shapes kit:

| Field | Supported values | Default when omitted |
| --- | --- | --- |
| `fill` | `none`, `ink`, `surface`, `accent`, `gray`, `blue`, `green`, `yellow`, `red`, `violet` | `blue`; text: `none` |
| `stroke` | Same colors as fill | `blue`; text: `none`; lines: `ink` |
| `width` | `1`, `2`, `4` (stroke width, not node width) | `2` |
| `dash` | Boolean | `false` |
| `radius` | `0`, `8` (rectangle corner radius) | `8`; text: `0` |
| `size` | `s`, `m`, `l` | `m` |
| `font` | `sans`, `heading`, `mono`, `handwritten` (text-bearing shapes only) | Inherit document `appearance.font` |
| `align` | `left`, `center`, `right` | `center`; text: `left` |
| `rotation` | Numeric degrees | `0` |
| `arrow` | `end`, `both`, `none` (standalone lines) | `end` |

Named colors resolve through the renderer's palette. Hue names such as `blue`,
`yellow`, and `red` retain their hue intent across themes. `ink`, `surface`, and
`accent` are theme-relative: this interface resolves accent to acid and surface
to a neutral fill. These remain names in the file, not resolved color values.

### Edges

Each edge requires stable non-empty string `id`, `source`, and `target` fields.
Endpoints reference existing node IDs. Optional fields:

- `source_handle`, `target_handle`: handle identifiers, or null for automatic
  attachment. Shapes accept side names such as `right` and `left`.
- `path`: `bezier` (default), `smooth`, `step`, or `straight`.
- `marker`: `arrow` (default), `dot`, or `none`.
- `label`: string or null.
- `animated`: boolean, default false.
- `data`: an application metadata object, default `{}`.

Self-loop edges use the same node ID for `source` and `target` and distinct named
side handles, for example `source_handle: "right"` and `target_handle: "top"`.
They remain ordinary edges in the version-1 format; no extra node or routing
metadata is required. Their exterior curve is computed by the renderer.

Node IDs are unique among nodes; edge IDs are unique among edges. Duplicate IDs
and dangling connections are errors, not instructions to generate replacements.

Optional top-level `paper` has `background` (`dots`, `lines`, `cross`, or `none`)
and `grid` (integer 4 through 200). Omitted values use the canvas defaults.

Unknown metadata fields at the top level and on retained nodes, edges, and paper
are preserved during saving. Unknown node types or unsupported format versions
are rejected rather than silently dropped. Saving normalizes formatting and may
make implicit Hakushi defaults explicit; it does not preserve source whitespace
or key ordering. Deleted objects and their metadata are removed.

To move or back up a canvas, copy its JSON file. Current documents have no external
assets, hidden storage, or database dependencies. Selection, viewport, and undo
history are session state and are not part of the file.

## Checks

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
node --check assets/js/app.js
mix assets.build
```

The permanent tests cover file round-trips, external changes, competing app saves,
metadata retention, document lettering, deletion, relocation, malformed documents,
stable IDs, permissions, and refusing to overwrite existing files. Selected-file
consumer tests also cover validated content loading, server-path isolation,
prepared-save metadata, snapshot acknowledgements with newer edits, copy-download
dirty state, and stale reload/save rejection.

Native-picker smoke checks use temporary documents, never the editable welcome
source. Actual browser checks exercised input-file chooser selection/cancellation,
invalid content, pending text flushing, dirty Open protection, and a downloaded
copy reread from disk with source bytes unchanged. A separate temporary,
genuine Origin Private File System handle exercised native read/write/close,
external-revision refusal, reload, and an in-flight save acknowledgement that
kept newer edits dirty; only picker acquisition and write timing were instrumented.
That verifies the handle code path, **not an OS-selected file or permission dialog**.
Puppeteer cannot intercept `showOpenFilePicker` dialogs; see its
[documented interception limit](https://pptr.dev/api/puppeteer.page.waitforfilechooser).

Hakushi 0.7.0 is the published Hex release used here. Its optional Issho integration
currently emits an upstream undefined-module warning when compiled without Issho;
this application does not enable collaboration or add that dependency merely to
silence the warning.

Freehand drawing, external Markdown notes, attachments, cloud storage, multiplayer,
agent APIs, and automatic conflict merging are outside this initial slice.
