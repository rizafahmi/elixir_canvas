# Project conventions

Read [DESIGN.md](DESIGN.md) before changing the interface. Elixir Canvas uses its
light-first Neo-Acid adaptation, with shared primitives in `assets/css/tokens.css`
and workspace overrides in `assets/css/app.css`.

Keep floating controls, square corners, flat surfaces, and the canvas as the main
visual surface. Acid identifies the active tool; neutral hover must not look like
selection. Use cobalt for object selection and keyboard focus. Documents store
named colors and generic typography roles, not resolved theme values. Resolve
drawing appearance through the renderer's theme mapping; changing a view's theme
must not dirty the document or rewrite saved geometry, color names, or font roles.

Fonts are vendored in `priv/static/fonts/neo-acid`: Unbounded 800, Mona Sans
400/700, and Monaspace Neon 400/700 only (five Neo-Acid faces). This approved
project pairing overrides the vendored skill's font list, not its other guardrails.
The renderer maps generic sans, heading, and mono drawing roles through the shared
body, display, and mono CSS tokens; handwritten uses separately bundled Amatic SC
700. Drawing sans/mono stay 400 with large emphasis 700; headings stay 800.
Preserve authored geometry and corner choices. Wait for the resolved drawing
font before canvas measurement or editing.
Shapes may store a generic `data.font` override; absent means document default.
The inspector shows the effective role; selecting a style saves an explicit role.
Typography changes do not resize authored boxes; editors and exports honor each role.
No npm installation is required to run the application.

Run locally with `mix phx.server`. Verify visual changes in the actual editor,
including narrow layouts and open panels. Use a temporary canvas when exercising
save behavior; `examples/welcome.json` is a real editable source file.
