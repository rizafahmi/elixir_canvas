# Agent context

## Product and trust boundary

Elixir Canvas is a local-file-first spatial thinking canvas built with Elixir,
Phoenix LiveView, and Hakushi. JSON files are the actual documents, not database
exports. There is no database in the current application.

The server is local and unauthenticated, with access to the machine's filesystem;
it is not a hosted multi-user service. Keep this trust boundary explicit.
Databases, accounts, cloud storage, and multiplayer are outside the current scope
unless requested, not permanently prohibited directions.

## Architecture map

- [Document](lib/elixir_canvas/document.ex) owns version-1 JSON validation,
  metadata retention, source identity, and server-file persistence.
- [CanvasLive](lib/elixir_canvas_web/live/canvas_live.ex) coordinates the editor,
  document lifecycle, unsaved state, and save/reload flows.
- [DrawingShapes](lib/elixir_canvas_web/drawing_shapes.ex) and
  [DrawingTypography](lib/elixir_canvas_web/drawing_typography.ex) adapt Hakushi's
  Shapes kit for unfilled Neo-Acid defaults, standalone lines, and portable font roles.
- Hakushi owns graph operations and undo/redo; Document bridges its graph to the
  portable file contract.
- [app.js](assets/js/app.js) integrates LiveView and Hakushi in the browser,
  including drawing-font readiness and editor behavior, alongside
  [rotation_guides.js](assets/js/rotation_guides.js) and
  [self_loops.js](assets/js/self_loops.js).
- [native_file.js](assets/js/native_file.js) handles browser file selection,
  native-handle persistence, and copy-download fallbacks.
- [tokens.css](assets/css/tokens.css) holds shared design primitives;
  [app.css](assets/css/app.css) applies workspace and drawing styles.
- [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
  [LICENSE](LICENSE) define open-source contributor checks, local-server security
  boundaries, and MIT/font licensing.

## Document and data safety

Preserve compatibility with existing version-1 canvas files. Discuss format
changes before implementing them. The canonical schema and round-trip rules are
in [README: Document format](README.md#document-format-version-1).

Preserve metadata on retained objects, authored geometry and corner choices,
portable named colors, and generic typography roles. Resolve theme colors and
font families in the renderer; changing a view's theme must not dirty documents
or rewrite their geometry or style names. Wait for the resolved drawing font
before measuring canvas text or enabling editing.

A browser-selected filename is not a server path. Never infer a server location
from it or redirect its Save to the initial document. Keep server-path files,
browser handles, and downloaded copies distinct, including truthful save/dirty
state and external-change handling. See [README: Run](README.md#run) and
[README: Edit](README.md#edit) for the persistence contract and its limits.

## Decision policies

Implement requested changes directly by default. Restate the plan and wait only
when explicitly requested. Commit only when requested.

Reuse the existing Elixir/Phoenix/LiveView/Hakushi stack and vanilla CSS. Ask before
adding any dependency or build step; this does not prohibit using existing ones.

Core desktop behavior should work in Chrome, Edge, Safari, and Firefox. Use
progressive enhancement: feature-detect optional browser APIs and provide honest
fallbacks rather than implying unsupported capabilities succeeded.

## Design guidance

Read [DESIGN.md](DESIGN.md) before interface changes, prioritizing its opening
Elixir Canvas adaptation over the source kit's generic defaults. Keep the canvas
dominant, with floating controls, square corners, and flat surfaces. Acid marks
the active tool; hover stays neutral. Cobalt marks object selection and focus.

The approved Mona Sans/Monaspace Neon project pairing overrides the vendored
design skill's font list, not its other guardrails. See
[DESIGN: Typography](DESIGN.md#3-typography) for font inventory, weights, role
mapping, and inspector behavior rather than duplicating those rules here.

## Setup and verification

[README: Run](README.md#run) is canonical for prerequisites and local setup;
no npm installation is required. [README: Checks](README.md#checks) lists the
verification commands and browser-check limits. Mix aliases are defined in
[mix.exs](mix.exs); `mix precommit` formats files and can change the lockfile,
so it is not a read-only check.

Verify visual changes in the actual editor, including narrow layouts and open
panels. Narrow-layout checks are not mobile interaction testing. Use temporary
canvases to exercise saves: [examples/welcome.json](examples/welcome.json) is a
real editable source document, not a disposable fixture.

## Completion evidence

Before behavior changes, identify the user scenario, observable expected outcomes,
and relevant failure cases. Derive expectations from requirements, not implementation.
Run relevant existing checks; passing builds/tests alone is not proof. Exercise the
real changed surface and inspect actual state and side effects, not callbacks,
logs, screenshots, or self-reports alone.

For bugs, establish failing evidence and root cause, then repeat the same scenario
after the fix. Add a useful deterministic regression when practical. Permanent tests
should protect behavior contracts through refactors, not private helpers, copied
constants, source structure, or incidental wording.

For persistence, use the temporary canvases described above: verify real saved bytes
and dirty state, plus relevant cancellation, failure, conflict, and fallback paths.
Report executed checks, observed outcomes, and material limits honestly. Masking an
API does not establish Safari/Firefox compatibility; OPFS does not exercise an OS
file dialog.

For docs-only changes, review content, paths, and links; no app run is needed unless
behavior also changes.

## Artifact maintenance

Before declaring significant behavior, architecture, setup, verification, file-format,
or workflow changes complete, review AGENTS.md and README.md plus affected docs,
examples, and verification instructions as relevant. Update stale guidance,
paths, and contracts; remove obsolete claims in the same change, aligned with
verified behavior. Keep durable agent context and policies in AGENTS.md; setup,
user behavior, schemas, and check recipes in README.md; visual rules in DESIGN.md.
Avoid duplication. Accurate files may remain unchanged; whitespace-only changes
need no review. Briefly report artifacts updated or reviewed unchanged, without
a ceremonial checklist.
