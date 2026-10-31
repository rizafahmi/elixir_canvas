---
name: neo-acid
description: Light-first Elixir Canvas adaptation of the brutalist Neo-Acid Gallery foundation of rizafahmi.com with utilitarian highlighter playbooks and Mona Sans/Monaspace Neon typography inspired by github/lever.
colors:
  neutral-dark-bg: "#121519"
  neutral-dark-surface: "#1b2026"
  neutral-dark-elevated: "#222831"
  neutral-dark-text: "#c2cad6"
  neutral-dark-heading: "#e7ecf2"
  neutral-dark-muted: "#8c96a3"
  neutral-dark-border-strong: "#434a56"
  neutral-dark-border-subtle: "#262c36"
  neutral-light-bg: "#f7f7f5"
  neutral-light-surface: "#ecece6"
  neutral-light-elevated: "#ffffff"
  neutral-light-text: "#3f454d"
  neutral-light-heading: "#0a0b0d"
  neutral-light-muted: "#6e7882"
  neutral-light-border-strong: "#0a0b0d"
  neutral-light-border-subtle: "#d8dad3"
  highlighter-ink: "#0a0b0d"
  hl-acid: "#c5f82a"
  hl-violet: "#a984ff"
  hl-mint: "#5ae67a"
  hl-sky: "#8ce0ff"
  hl-magenta: "#ff6ed4"
  accent-cobalt: "#1a3bf5"
typography:
  display:
    fontFamily: "Unbounded, system-ui, sans-serif"
    fontSize: "2.5rem"
    fontWeight: 800
    lineHeight: 1.15
  body:
    fontFamily: "Mona Sans, system-ui, sans-serif"
    fontSize: "1.0625rem"
    fontWeight: 400
    lineHeight: 1.6
  mono:
    fontFamily: "Monaspace Neon, JetBrains Mono, monospace"
    fontSize: "0.875rem"
    fontWeight: 700
    lineHeight: 1.4
rounded:
  none: "0px"
  sm: "2px"
components:
  button-primary:
    backgroundColor: "{colors.neutral-dark-heading}"
    textColor: "{colors.neutral-dark-bg}"
    hoverBackgroundColor: "{colors.hl-acid}"
    hoverTextColor: "{colors.highlighter-ink}"
    rounded: "{rounded.none}"
    padding: "0.75rem 1.25rem"
    border: "2px solid {colors.neutral-dark-border-strong}"
  badge-highlighter:
    backgroundColor: "{colors.hl-acid}"
    textColor: "{colors.highlighter-ink}"
    rounded: "{rounded.none}"
    padding: "0.15rem 0.45rem"
  card-brutalist:
    backgroundColor: "transparent"
    border: "2px solid {colors.neutral-dark-border-strong}"
    padding: "1.5rem"
    rounded: "{rounded.none}"
---

# Design System: Neo-Acid (`neo-acid`)

> **Elixir Canvas adaptation:** Start in light mode with `data-theme="light"` on
> the root HTML element. Keep the canvas dominant and retain floating controls
> rather than adding a full-width navbar or footer. Active tools use acid fills;
> tool hover remains neutral to distinguish hover from selection. Cobalt marks
> object selection and focus. Documents retain named colors and generic typography
> roles; the renderer maps them to the current theme's palette and font families.
> Switching renderer styling must not dirty files or rewrite authored geometry or
> style names. Hue names preserve their hue; accent and surface are theme-relative.
> Shared dark-first palette tokens remain available; a dark-mode switch is not
> part of this design pass. The approved Mona Sans/Monaspace Neon pairing replaces
> the source kit's body/mono fonts while preserving all other Neo-Acid guardrails.
>
> **Control layout:** Paper and the file menu occupy the top left; Download and
> Save occupy the top right. Drawing tools and Style share a bottom dock, with
> Style's inspector above the dock. Undo and redo lead the left rail; a live zoom
> percentage opens a non-modal popover to its right for zoom out/in, Fit to screen,
> and Reset to 100%. Opening it must preserve zoom; repeated adjustments keep it
> open, and Escape or outside clicks dismiss it. Arrangement remains a separate
> group. The rail ends above the dock and scrolls in short windows. Narrow windows
> collapse Download and, at the smallest width, Style to labeled icons. All drawing
> tools remain visible.

## 1. Overview

**Creative North Star: "The Neo-Acid Highlighter Gallery"**

A dark-first, high-contrast brutalist application design system that combines the bold typographic presence of `rizafahmi.com` ("Neo-Acid Gallery") with the semantic marker-highlighter system and calm data density of `github/lever`.

### Key Characteristics

- **Dark-First Obsidian Canvas**: Defaults to softened Obsidian Clay (`#121519`) with Silver White (`#e7ecf2`) headings and Slate (`#8c96a3`) secondary copy; switches cleanly to warm Raw Gallery Plaster (`#f7f7f5`) via `[data-theme="light"]`.
- **Ultra-Wide Display + Two-Tone Phrasing**: Headlines use `Unbounded` (`800` weight) and pair primary white/ebony hooks with muted slate continuations in the same block.
- **Semantic Highlighter Swatches**: Five high-luminance marker tokens (`--hl-acid`, `--hl-violet`, `--hl-mint`, `--hl-sky`, `--hl-magenta`) encode action verbs, categories, and system states.
- **Dual Border Architecture**: Thick `2px`/`4px` solid structural frames paired with whisper-quiet `1px` dividers inside dense lists, command playbooks, and tables.
- **Tactile Color Drenches**: Interactive buttons, nav pills, and cards drench completely with `--hl-acid` (and `#0a0b0d` ink) on hover.

---

## 2. Colors

### Base Surfaces & Ink (Dark Mode Default — `:root`)

- **Obsidian Clay** (`#121519` / `--bg-canvas`): Default dark application background.
- **Obsidian Surface** (`#1b2026` / `--bg-surface`): Subtle row hovers, table headers, and callout fills.
- **Obsidian Elevated** (`#222831` / `--bg-elevated`): Dropdown menus and form inputs.
- **Silver White** (`#e7ecf2` / `--text-primary`): Primary headings and high-emphasis copy.
- **Plaster Gray** (`#c2cad6` / `--text-secondary`): Comfortable long-form body text.
- **Slate Dark** (`#8c96a3` / `--text-muted`): Muted headline continuations, kickers, and right-aligned command notes.

### Light Mode Overrides (`[data-theme="light"]`)

- **Raw Gallery Plaster** (`#f7f7f5` / `--bg-canvas`): Warm off-white background.
- **Plaster Alt** (`#ecece6` / `--bg-surface`): Subtle surface fill for table headers and callouts.
- **Ebony Ink** (`#0a0b0d` / `--text-primary`): Crisp near-black text and structural borders.
- **Slate Light** (`#6e7882` / `--text-muted`): Muted headline continuations and metadata notes.

### Semantic Highlighter Swatches

Every highlighter swatch is calibrated to achieve **WCAG AAA (>7:1)** contrast against **Ebony Ink (`#0a0b0d` / `--hl-ink`)**:

| Token | Hex | Contrast vs `#0a0b0d` | Semantic Meaning |
| :--- | :--- | :--- | :--- |
| `--hl-acid` | `#c5f82a` | **16.4 : 1 (AAA)** | Primary brand anchor, active tab/nav, hero banner, primary hover drench |
| `--hl-violet` | `#a984ff` | **7.2 : 1 (AAA)** | **Build / Create** — new features, specs (`brief`), architecture (`refactor`) |
| `--hl-mint` | `#5ae67a` | **12.5 : 1 (AAA)** | **Loop / Shipped** — benchmarks, verification, passing checks, active status |
| `--hl-sky` | `#8ce0ff` | **13.6 : 1 (AAA)** | **Run / Automate** — scheduled jobs, CI/CD, background agents, info callouts |
| `--hl-magenta` | `#ff6ed4` | **7.8 : 1 (AAA)** | **You / Guardrails** — user preferences (`steer`, `autonomy`), destructive hover |
| `--accent-cobalt` | `#1a3bf5` | **8.6 : 1 (vs `#fff`)** | Secondary structural action, light-mode prose links and focus rings |

### Named Rules

- **The Highlighter Ink Rule:** Highlighter swatches (`--hl-*`) are **background fills**, never text colors on light surfaces. Text inside any `.hl` or `<mark data-hl>` element must always use `--hl-ink` (`#0a0b0d`), even in dark mode.
- **The Color Structure Rule:** Static application chrome is predominantly monochrome (silver/slate on obsidian, or ebony/slate on plaster). Color is reserved for semantic `.hl` badges, status indicators, and tactile hover/focus states.

---

## 3. Typography

- **Display Font (`--font-display`):** `Unbounded` (Extra Bold `800` only)
- **Body Font (`--font-body`):** `Mona Sans` (Regular `400`, Bold `700`)
- **Mono/Label Font (`--font-mono`):** `Monaspace Neon` (Regular `400`, Bold `700`)

Drawing documents save only `sans`, `heading`, `mono`, or `handwritten`, never
family names. The renderer resolves `sans` through `--font-body`, `heading` through
`--font-display`, and `mono` through `--font-mono`; handwritten remains the separate
`Amatic SC 700` face. Sans and mono drawing text use `400` normally and `700` for
large emphasis; heading text always uses `800`. Font loading must resolve these
CSS roles before measurement or editing without changing saved geometry.

### Hierarchy

- **Two-Tone Hero Headline (`.headline-two-tone`)**: `Unbounded 800`, `clamp(1.65rem, 3.6vw, 2.5rem)`, line-height `1.15`.
- **Section Heading (`h2`)**: `Unbounded 800`, `1.5rem–1.75rem`, line-height `1.15`.
- **Section Kicker (`.section-kicker`)**: `Monaspace Neon 700`, `0.75rem`, uppercase, `letter-spacing: 0.06em`, `--text-muted`.
- **Body Copy**: `Mona Sans 400`, `1.0625rem`, line-height `1.6`, capped at `65ch` for reading views.

### Named Rules

- **The Five Face Rule:** Ship exactly five Neo-Acid WOFF2 faces: `Unbounded 800`, `Mona Sans 400/700`, and `Monaspace Neon 400/700`, plus the separate `Amatic SC 700` handwritten face. The five Neo-Acid files total 152,796 bytes (about 153KB / 149.2KiB), excluding handwriting; this approved pairing replaces the source kit's 87KB budget. Keep the Latin subsets and only these normal weights, including real `700` faces rather than synthesized bold. Never load additional weights of `Unbounded` (like `400` or `700`) or italic font files (use browser-synthesized oblique for blockquotes).
- **The Two-Tone Headline Rule:** Write conversational headlines inside a single heading element where the primary statement uses `--text-primary` and the continuation wraps in `<span class="muted">` (`--text-muted`). Both stay at `font-weight: 800` so the contrast comes from color, not an extra font file.

---

## 4. Elevation & Borders

We reject drop shadows, blurs, and gradients. Hierarchy is expressed strictly through border weight and surface contrast.

- **Major Split (`--border-split`):** `4px solid var(--border-strong-color)` — used for top app navbar and bottom app footer boundaries.
- **Structural Frame (`--border-frame`):** `2px solid var(--border-strong-color)` — used for cards, buttons, inputs, dropdown menus, tables, and media frames.
- **Dense Row Divider (`--border-row`):** `1px solid var(--border-subtle-color)` — used inside `.command-list` rows and `.app-table` body cells.
- **Corner Radius (`--radius-none`):** `0px` across all buttons, badges, inputs, cards, and menus.

### Named Rules

- **The Dual Border Rule:** Use `2px`/`4px` borders to frame components and page regions, but drop to `1px solid var(--border-subtle-color)` for repeating rows inside lists and tables so dense data UIs never feel visually noisy.

---

## 5. Components

All reference implementations live in `tokens.css` and `specimen.html`:

1. **App Navbar & Sub-Nav (`.app-navbar`, `.app-tabs`, `.app-breadcrumbs`)**:Bounded by a `4px` bottom border. Nav items (`.app-nav-item`) are square-edged `Monaspace Neon` links that fill with `--hl-acid` and `--hl-ink` on hover or `.is-active`.
2. **Buttons & Segmented Controls (`.btn`, `.btn-secondary`, `.btn-acid`, `.btn-cobalt`, `.btn-danger`, `.btn-group`)**: `2px` solid border, `0px` radius, `Monaspace Neon 700`. Primary buttons invert canvas/ink and drench with `--hl-acid` on hover. Destructive buttons (`.btn-danger`) drench with `--hl-magenta` on hover.
3. **Menus & Playbook Lists (`.menu-dropdown`, `.menu-item`, `.command-list`, `.command-row`)**: Dropdown menus use a `2px` frame on `--bg-elevated` with `.hl` verb badges and `.menu-kbd` shortcut hints. Command lists use `1px` row borders with a muted prefix (`/lever`), a `.hl` verb pill, the prompt string, and a right-aligned muted `.note`.
4. **Links (`.prose-link`, `.action-link`, `.card-interactive`)**: In-text links carry a `3px` underline (`--hl-acid` in dark mode, `--accent-cobalt` in light mode) and drench on hover. Whole-card links (`.card-interactive`) drench the entire card surface with `--hl-acid` and switch all inner text (including `.text-muted` and `.section-kicker`) to `--hl-ink` (`#0a0b0d`) so contrast never fails.
5. **Forms & Command Bar (`.command-input-wrap`, `.input`, `.select`, `.check-input`)**: Sharp `0px` inputs on `--bg-elevated` with an inset `2px` focus ring (`--hl-acid` in dark, `--accent-cobalt` in light). `.command-input-wrap` pairs a hard-bordered `--hl-acid` prefix block (`/lever`) with a monospace text input.
6. **Brutalist Media Frame (`.media-frame`, `.media-canvas`, `.media-caption`, `.media-badge`)**: Wraps images, charts, or video facades in a `2px` border with an absolute top-left `.hl` badge and a `2px` top-bordered `Monaspace Neon` metadata caption bar.
7. **Tables & Callouts (`.app-table`, `.callout`)**: Tables use a `2px` outer border and `1px` row dividers. Callouts use a `2px` frame with an `8px` left highlighter border (`.callout-mint`, `.callout-magenta`, `.callout-acid`, `.callout-violet`, `.callout-sky`).
8. **App Footer (`.app-footer`, `.app-footer-grid`, `.app-footer-colophon`, `.status-dot`)**: `4px` top border, multi-column sitemap links, a square `--hl-mint` operational status indicator, and a bottom monospace colophon bar.

---

## 6. Do's and Don'ts

### Do's

- **Do** default to Dark Mode (`:root` Obsidian Clay `#121519`) and support `[data-theme="light"]` (`#f7f7f5`).
- **Do** keep text inside `.hl` / `<mark data-hl>` badges pinned to `#0a0b0d` (`--hl-ink`) in both themes.
- **Do** pair statistical figures (`.stat-value`) with their sample size and range in `Monaspace Neon`.
- **Do** combine `2px`/`4px` outer structural borders with `1px` subtle inner row dividers.

### Don'ts

- **Don't** use drop shadows (`box-shadow` for elevation), linear/radial gradients, or `backdrop-filter` glassmorphism.
- **Don't** round corners (`border-radius: 9999px` or `8px`) on pills, buttons, cards, or inputs — keep everything `0px`.
- **Don't** load extra font weights of `Unbounded` — keep the display family strictly at `800`.
- **Don't** center-align body copy or multi-line cards; keep alignment left-anchored and crisp.
