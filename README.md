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
  - A power toggle (does the same start/stop as the bar's right click).
  - A status pill that actually tells you what's wrong instead of staying
    silent: "Waynergy isn't installed or not on `PATH`." if it can't find
    the binary, or "Waynergy exited right after starting — check the IP
    and that the host is reachable." if a start attempt dies immediately.
  - A connection-details grid (Host, Port) — click the host IP to copy it.
  - A text field to change the host IP, saved with the checkmark button
    next to it.
  - A switch to show/hide the "Waynergy" label in the bar (leaves just the
    dot).
- **Middle click** — force a status refresh.
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
| Left click | Open the panel (status + power toggle + connection details + IP field + label switch) |
| Middle click | Refresh the running-state check immediately |

## How it works

- **Start:** `waynergy -c <ip> -p 24800 -E`, launched detached
  (`Quickshell.execDetached`) so it survives plugin reloads and isn't tied
  to the bar widget's lifetime.
- **Stop:** `pkill -x waynergy` (SIGTERM, matches by process name).
- **Status:** `pgrep -x waynergy`, polled every 5 seconds and right after
  every start/stop.
- **Installed check:** `which waynergy`, same pattern the built-in
  Tailscale plugin uses, checked on open and on every status poll.
- Port is fixed at `24800` and the `-E` flag is always passed, matching
  the command this plugin was built around. Only the IP is configurable.

## State files

The host IP and label-visibility setting are stored at:

```
~/.local/state/omarchy/io.github.aryan-techie.waynergy/settings.json
```

It's `{ "ip": "...", "showLabel": true }` — nothing else is written
anywhere on disk, and nothing is sent over the network by this plugin
itself (the IP is only ever handed to `waynergy` as a `-c` argument,
never shell-interpolated).

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
