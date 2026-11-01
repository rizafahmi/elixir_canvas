# Contributing to Elixir Canvas

Elixir Canvas is a local-file-first spatial thinking canvas built with Elixir,
Phoenix LiveView, and Hakushi. JSON files are the actual documents, not exports
from a database.

## Prerequisites and setup

Requires Elixir 1.18+ and a compatible Erlang/OTP (available via Nix or
`erlef/setup-beam`). No database or `npm install` step is needed; Mix fetches
Hex dependencies and the local `esbuild` binary.

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>. See [README: Run](README.md#run) for full usage
and persistence details.

## Architecture overview

- [`ElixirCanvas.Document`](lib/elixir_canvas/document.ex) — Version-1 JSON
  schema validation, unknown-metadata retention, SHA-256 revision checks, and
  atomic server-file persistence.
- [`ElixirCanvasWeb.CanvasLive`](lib/elixir_canvas_web/live/canvas_live.ex) —
  LiveView workspace coordinating Hakushi graph state, dirty tracking, and
  save/reload flows across server paths, browser file handles, and copy downloads.
- [`ElixirCanvasWeb.DrawingShapes`](lib/elixir_canvas_web/drawing_shapes.ex) and
  [`ElixirCanvasWeb.DrawingTypography`](lib/elixir_canvas_web/drawing_typography.ex) —
  Custom Hakushi shape kit with unfilled Neo-Acid defaults, standalone lines, and
  portable typography roles.
- [`assets/js/app.js`](assets/js/app.js),
  [`assets/js/native_file.js`](assets/js/native_file.js),
  [`assets/js/rotation_guides.js`](assets/js/rotation_guides.js), and
  [`assets/js/self_loops.js`](assets/js/self_loops.js) — Browser integration for
  font readiness, File System Access handles and copy-download fallbacks, rotated
  selection/resizing, and exterior self-loop arrows.
- [`assets/css/tokens.css`](assets/css/tokens.css) and
  [`assets/css/app.css`](assets/css/app.css) — Light-first Neo-Acid design
  tokens and workspace styling. Read [DESIGN.md](DESIGN.md) before modifying UI
  components, colors, or typography.

## Core invariants

1. **Preserve version-1 file compatibility.** Discuss schema changes in an issue
   before implementing them. Retain unknown metadata on top-level objects,
   retained nodes, edges, and paper settings.
2. **Keep document styling portable.** Files store generic typography roles
   (`sans`, `heading`, `mono`, `handwritten`) and semantic/hue color names
   (`ink`, `surface`, `accent`, `gray`, `blue`, `green`, `yellow`, `red`,
   `violet`, `none`), never resolved hex values or font-family names. Changing a
   view's theme or font role must not rewrite authored geometry.
3. **Keep persistence modes honest and distinct.** Never infer a server file
   path from a browser-selected filename or redirect its save to the startup
   document. Server paths, browser `FileSystemFileHandle` sessions, and
   `Save copy` downloads have separate save, reload, and dirty-state rules.
4. **Keep dependencies minimal.** Reuse the existing Elixir, Phoenix LiveView,
   Hakushi, and vanilla CSS stack. Discuss new dependencies or build steps
   before adding them.
5. **Do not use `examples/welcome.json` as a disposable test fixture.** Always
   test saves against temporary copies (see [README: Manual browser verification](README.md#manual-browser-verification)).

## Verification before opening a pull request

Run the full check suite from the repository root:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
node --check assets/js/app.js
node --check assets/js/native_file.js
node --check assets/js/rotation_guides.js
node --check assets/js/self_loops.js
mix assets.build
```

For UI or persistence changes, verify behavior in a real browser using a
disposable temporary canvas copy as documented in
[README: Manual browser verification](README.md#manual-browser-verification),
including narrow viewports (down to 320px) and open menus/inspectors.
