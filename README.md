# Elixir Canvas

A local-file-first spatial thinking canvas built with Elixir, Phoenix LiveView,
and Hakushi. The JSON file is the document, not an export from a database.

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

The source-path field opens existing files on the machine running Phoenix.
The new-file field creates an empty document at a path whose parent directory
already exists. Creation refuses to replace an existing file. Paths can be
absolute or relative to the server's working directory.

**Keep the server local.** It intentionally has access to local files, without
accounts or access controls. Development and production configurations bind to
IPv4 loopback. This is not a hosted multi-user application.

## Edit

- Use the canvas toolbar for rectangles, ellipses, diamonds, triangles, text,
  and lines. Drag between shape handles to create a connected arrow.
- Double-click a shape to edit its text. Select it to resize, rotate, or style it.
- Pan with Space + drag; use the bottom-left controls to zoom or fit the canvas.
- Undo and redo are provided by Hakushi. Reloading the source resets that history.
- Save explicitly with **Save**, Command-S, or Control-S. Saving commits an active
  shape text editor and waits for Hakushi's resulting changes, including automatic
  text-box growth. Unsaved changes live in memory until saved, not in a database.
- Edit the JSON in an ordinary text editor, then use **Reload** to read it back.
  Reload asks before discarding unsaved graphical edits.

The app checks the source file once a second. A detected external modification,
removal, or read failure leaves the current canvas intact. Saving also checks the
last-read SHA-256 revision, so it refuses stale writes even before the next check.
An invalid file produces an error rather than replacing the open graph.

Saves write and sync a temporary sibling file, preserve permission bits, check
that the source revision still matches, and rename the temporary file over the
source. App saves to the same path are serialized across tabs. These are
optimistic checks, **not a filesystem compare-and-swap or a lock respected by
other editors**: an external write racing the final check and rename is not
excluded. Take turns editing externally; automatic merging is deliberately absent.
Symbolic links are refused rather than replaced. Save does not preserve extended
attributes or provide power-loss durability guarantees for the parent directory.

## Document format: version 1

See `examples/welcome.json` for a hand-written document. Files use UTF-8 JSON with
three required top-level fields: integer `version: 1`, an ordered `nodes` array,
and an `edges` array. This is an app-owned format based on Hakushi 0.7's graph
serialization, not the JSON Canvas standard.

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
- `shape-line`: a standalone line. `data.from` and `data.to` are `[x, y]` endpoint
  pairs relative to the node's box. Connections between objects belong in `edges`.

Style fields in `data` follow the Shapes kit:

| Field | Supported values | Default when omitted |
| --- | --- | --- |
| `fill` | `none`, `ink`, `gray`, `blue`, `green`, `yellow`, `red`, `violet` | `blue`; text: `none` |
| `stroke` | Same colors as fill | `blue`; text: `none`; lines: `ink` |
| `width` | `1`, `2`, `4` (stroke width, not node width) | `2` |
| `dash` | Boolean | `false` |
| `radius` | `0`, `8` (rectangle corner radius) | `8`; text: `0` |
| `size` | `s`, `m`, `l` | `m` |
| `align` | `left`, `center`, `right` | `center`; text: `left` |
| `rotation` | Numeric degrees | `0` |
| `arrow` | `end`, `both`, `none` (standalone lines) | `end` |

Named colors resolve through the app's local theme. The file describes structure
and styling intent; it does not embed fonts or guarantee pixel-identical rendering
in unrelated software.

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
metadata retention, deletion, relocation, malformed documents, stable IDs,
permissions, and refusing to overwrite existing files.

Hakushi 0.7.0 is the published Hex release used here. Its optional Issho integration
currently emits an upstream undefined-module warning when compiled without Issho;
this application does not enable collaboration or add that dependency merely to
silence the warning.

Freehand drawing, external Markdown notes, attachments, cloud storage, multiplayer,
agent APIs, and automatic conflict merging are outside this initial slice.
