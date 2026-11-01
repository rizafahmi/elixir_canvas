# Security Policy

## Trust boundary and intended deployment

Elixir Canvas is a **local-first desktop/workstation tool**, not a hosted
multi-user web service.

- The Phoenix server runs without user accounts or authentication and has
  intentional read/write access to the local user's filesystem for server-path
  canvases.
- Both development (`config/dev.exs`) and production (`config/runtime.exs`)
  configurations bind to IPv4 loopback (`127.0.0.1`) by default.
- **Do not expose the server to untrusted networks or the public internet.**

## Built-in file and data safety controls

Within its local-workstation trust boundary, Elixir Canvas enforces several
safety boundaries:

1. **Browser-selected file isolation:** Opening a file through the browser picker
   (`Open…`) sends validated file bytes and a display filename, never a server
   path. Browser-selected files cannot read, overwrite, or redirect saves to
   server-side paths (including the initial `CANVAS_FILE`).
2. **Symlink refusal and non-destructive creation:** Server-path operations
   (`ElixirCanvas.Document.open/1`, `create/1`, `save/2`) inspect `File.lstat/1`
   and refuse symbolic links. Creating a new server canvas uses `:exclusive` file
   creation and never overwrites an existing file.
3. **Atomic sibling writes and optimistic revision checks:** Server-path saves
   write and `fsync` a temporary sibling file, preserve permission bits, verify
   the SHA-256 revision of the last-read bytes, and atomically rename over the
   target. Browser-handle saves verify the file's SHA-256 digest before and
   after writing to the exclusive stream.
4. **Strict version-1 decoding:** Untrusted or malformed JSON files are validated
   before replacing the active canvas graph. Invalid schemas, unsupported node
   types, duplicate IDs, dangling edges, and oversized text fields (>2,000
   Unicode characters) are rejected without modifying the open document or disk
   source.

## In-scope security issues

Please report vulnerabilities that violate the guarantees above, including:

- Cross-site scripting (XSS) or code execution triggered by opening a crafted
  `.json` canvas file.
- Browser-selected file operations (`selected-open`, `selected-reload`,
  `selected-saved`) reading or writing server filesystem paths.
- Bypassing symlink refusal or overwriting arbitrary files during `create` or
  stale-revision `save` operations.
- Default configurations binding to non-loopback interfaces without explicit
  operator opt-in.

## Reporting a vulnerability

Report suspected vulnerabilities privately via
[GitHub Security Advisories](https://github.com/rizafahmi/elixir_canvas/security/advisories/new)
rather than opening a public issue. Include a minimal reproduction (such as a
crafted JSON payload or request sequence) and the affected commit hash.
