# Changelog

All notable user-facing changes to this plugin. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## v1.1.0 — Keyboard shortcut and full keyboard navigation

### Added

- Optional global keyboard shortcut (`Ctrl+Super+Y` by default, or record your own) to
  open the panel from anywhere, applied to `~/.config/hypr/bindings.lua` with an
  automatic backup and rollback on a bad reload — same mechanism as the todoist plugin.
- The panel is now fully keyboard-navigable: Up/Down (or j/k) moves a highlight between
  every control (power toggle, IP field, Save, label switch, keyboard-shortcut buttons),
  Space/Enter activates whichever one is highlighted, and Escape backs out of the IP
  field before closing the panel instead of closing it immediately.
- The panel now scrolls if its content grows taller than the screen allows.

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
