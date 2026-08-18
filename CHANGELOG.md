# Changelog

All notable user-facing changes to this plugin. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## v1.0.0 — Initial release

### Added

- Bar pill showing waynergy's running state (`●` running, `○` stopped), with an optional
  "Waynergy" label next to the dot that can be hidden from the panel.
- Right-click the bar pill to start/stop waynergy directly — no panel needed.
- Left-click opens a panel with a power toggle, a Host/Port connection-details grid, an IP
  field (with inline save) to change the target host, and the label-visibility switch.
- Detects whether `waynergy` is installed / on `PATH` and shows a clear status message
  instead of silently doing nothing — same for a start attempt that exits right away (bad
  IP, unreachable host).
- IPC handlers (`refresh`, `open`, `close`, `show`, `hide`, `toggle`, `start`, `stop`) for
  scripting from outside the shell.
