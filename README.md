<div align="center">

# Waynergy for Omarchy

**A one-click [waynergy](https://github.com/r-c-f/waynergy) start/stop bar widget for [Omarchy](https://omarchy.org/).**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FAryan-Techie%2Fomarchy-waynergy-plugin%2Fmain%2Fmanifest.json&query=%24.version&label=version&color=informational)](manifest.json)
[![Omarchy plugin](https://img.shields.io/badge/omarchy-plugin-6d4aff)](https://omarchy.org/)
[![Validate](https://github.com/Aryan-Techie/omarchy-waynergy-plugin/actions/workflows/validate.yml/badge.svg)](https://github.com/Aryan-Techie/omarchy-waynergy-plugin/actions/workflows/validate.yml)
[![Contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

</div>

Right-click the bar pill to start waynergy; right-click again to kill it.
Left-click opens a small panel with the status, a power toggle, connection
details, a field to change the host IP, and a switch to hide the "Waynergy"
text next to the dot — handy when the other PC's IP changes and you don't
want to touch a terminal.

## Contents

- [Who this is for](#who-this-is-for)
- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
  - [Keyboard shortcut](#keyboard-shortcut)
  - [Keyboard navigation inside the panel](#keyboard-navigation-inside-the-panel)
- [How it works](#how-it-works)
- [State files](#state-files)
- [Uninstalling](#uninstalling)
- [Contributing](#contributing)
- [Getting help](#getting-help)
- [Changelog](#changelog)
- [License](#license)
- [Author](#author)

## Who this is for

You use [waynergy](https://github.com/r-c-f/waynergy) (a Wayland-native
[Synergy](https://symless.com/synergy)-compatible client) to share one
keyboard and mouse across two PCs, and you're tired of opening a terminal
every time you want to connect, disconnect, or the other machine's IP
changes (DHCP renewal, switching networks, a fresh install). This plugin
puts start, stop, and the IP field one click away in your Omarchy bar
instead.

If you don't already run a waynergy/Synergy **server** on another machine,
this plugin has nothing to connect to — it's the client-side control only.

## Features

- Bar pill shows a filled dot (`●`) when running, a hollow one (`○`) when
  stopped, next to an optional "Waynergy" label — polled every 5s so it
  stays accurate even if waynergy exits on its own (e.g. the host became
  unreachable).
- **Right click** — toggle: starts `waynergy -c <ip> -p 24800 -E` if it's
  not running, kills it (`pkill -x waynergy`) if it is. No panel opens.
- **Left click** — opens a panel with:
  - A power toggle and a refresh button in the header, next to the status line.
  - A status pill that actually tells you what's wrong instead of staying
    silent: "Waynergy isn't installed or not on `PATH`." if it can't find
    the binary, or "Waynergy exited right after starting — check the IP
    and that the host is reachable." if a start attempt dies immediately.
  - A connection-details grid (Host, Port, live Uptime) — click the host IP
    to copy it.
  - A text field to change the host IP, saved with the checkmark button
    next to it.
  - **Known Hosts** — your last 5 saved IPs as one-click rows, so switching
    between two PCs doesn't mean retyping an address. Tap one to make it
    the active target (an already-running session keeps running against
    the old one until you restart it); forget one with the small ✕.
  - A switch to show/hide the "Waynergy" label in the bar (leaves just the
    dot).
  - A keyboard shortcut recorder — set once, works from anywhere.
- **Middle click** — force a status refresh.
- **Optional global keyboard shortcut** (`Ctrl+Super+Y` by default, or record
  your own) to open the panel without touching the mouse.
- **Fully keyboard-navigable panel** — Up/Down between every control, Space
  or Enter to activate whatever's highlighted, Escape to back out.
- No config file editing required — settings live in a small local JSON
  file, edited entirely from the panel.

## Requirements

- **Omarchy**, obviously — this is a Quickshell bar plugin, not a
  standalone app.
- The **[`waynergy`](https://github.com/r-c-f/waynergy) binary**, installed
  and reachable on `PATH` **for your graphical session** — not just your
  interactive shell. Quickshell launches it directly (no login shell
  sourced), so if it's installed somewhere only your `~/.bashrc`/`~/.zshrc`
  adds to `PATH` (e.g. `~/.local/bin`), also export that same directory in
  your Hyprland/systemd user session (e.g. `~/.config/hypr/*.conf` or
  `~/.config/environment.d/`), or install it to `/usr/local/bin` /
  `/usr/bin` instead. The panel's status pill will tell you plainly if
  waynergy can't be found at all.
- A **waynergy/Synergy server already running on the other PC**, reachable
  on TCP port `24800`. This plugin only drives the client side.
- **Network reachability** between this machine and that IP/port — same
  LAN, VPN, Tailscale, whatever gets you there. If the process dies right
  after starting, that's usually this.

## Install

```
omarchy plugin add https://github.com/Aryan-Techie/omarchy-waynergy-plugin.git --enable
```

Or, to develop/inspect it locally first:

```
omarchy plugin clone io.github.aryan-techie.waynergy --edit
```

(swap in this repo's contents, or just copy this folder to
`~/.config/omarchy/plugins/io.github.aryan-techie.waynergy/` directly and
run `omarchy-shell shell rescanPlugins` if it doesn't pick up right away).

## Usage

| Action | Effect |
|---|---|
| Right click | Start waynergy if stopped, kill it if running |
| Left click | Open the panel (status + power toggle + connection details + IP field + Known Hosts + label switch + keyboard shortcut) |
| Middle click | Refresh the running-state check immediately |

### Keyboard shortcut

No shortcut is set by default — open the panel once (left-click the bar
pill) and use the **Keyboard shortcut** section at the bottom:

- **Ctrl+Super+Y** — applies that combo immediately.
- **Record custom…** — press it into the box (needs at least one modifier:
  Super/Ctrl/Alt/Shift), then **Apply**. **Esc** cancels the recording.
- **Remove** — clears whatever shortcut is currently set.

Applying writes a line to `~/.config/hypr/bindings.lua` (backed up first as
`bindings.lua.bak.<timestamp>`) and reloads Hyprland. If the reload reports
a config error, the backup is restored automatically and nothing changes.

### Keyboard navigation inside the panel

Once the panel is open:

- **Up / Down** (or **j** / **k**) — move the highlight between every
  control: the power toggle, the refresh button, the IP field, the Save
  button, any Known Hosts rows, the label switch, and the keyboard-shortcut
  buttons.
- **Space** or **Enter** — activate whatever's highlighted: flips a toggle,
  focuses the IP field for typing, or clicks a button.
- **Escape** — while actually typing in the IP field, the first Escape just
  exits typing and returns to the highlight (doesn't close the panel); a
  second Escape (or one from anywhere else) closes the panel.

## How it works

- **Start:** `waynergy -c <ip> -p 24800 -E`, launched detached
  (`Quickshell.execDetached`) so it survives plugin reloads and isn't tied
  to the bar widget's lifetime.
- **Stop:** `pkill -x waynergy` (SIGTERM, matches by process name).
- **Status:** `pgrep -x waynergy`, polled every 5 seconds and right after
  every start/stop.
- **Installed check:** `which waynergy`, same pattern the built-in
  Tailscale plugin uses, checked on open and on every status poll.
- **Keyboard shortcut:** a line appended to `~/.config/hypr/bindings.lua`
  calling `omarchy-shell shell toggle io.github.aryan-techie.waynergy`,
  applied via a backup-first, auto-rollback-on-error script (same mechanism
  the todoist plugin uses for its own shortcut).
- Port is fixed at `24800` and the `-E` flag is always passed, matching
  the command this plugin was built around. Only the IP is configurable.

## State files

The host IP, label-visibility setting, keyboard shortcut, and the last 5
saved IPs (Known Hosts) are stored at:

```
~/.local/state/omarchy/io.github.aryan-techie.waynergy/settings.json
```

It's `{ "ip": "...", "showLabel": true, "keybind": "...", "recentIps": [...] }`
— nothing else is written anywhere on disk except the one
`~/.config/hypr/bindings.lua` line described above, and nothing is sent
over the network by this plugin itself (the IP is only ever handed to
`waynergy` as a `-c` argument, never shell-interpolated).

## Uninstalling

```
omarchy plugin remove io.github.aryan-techie.waynergy
```

This removes the plugin and its bar entry. Delete the state directory
above too if you want the saved IP gone as well.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) — project layout, the conventions
worth knowing before you dig in, and how to test a change locally.

## Getting help

Open an issue with the plugin version (`manifest.json`'s `version`
field), what you expected vs. what happened, and `qs log -p
"$OMARCHY_PATH/shell" --tail 100` output if it's a crash or a silent
failure.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).

## Author

[aryan-techie](https://github.com/aryan-techie)
