# Security Policy

## Scope

This plugin runs [`waynergy`](https://github.com/r-c-f/waynergy) locally — waynergy
handles the actual connection on its own, exactly as if you'd typed the command yourself
in a terminal. The plugin itself only ever makes one network-touching call of its own: a
bare TCP connect attempt to whatever host:port you've configured, purely to check it's
reachable (no data sent, nothing read back beyond success/failure). It's worth reading the
README's [How it works](README.md#how-it-works) and [State files](README.md#state-files)
sections for the full picture — that's the baseline this policy assumes.

In short:

- This plugin persists `~/.local/state/omarchy/io.github.aryan-techie.waynergy/settings.json` (a host, a port, a label-visibility flag, and, if you've set one, your keyboard shortcut combo) and `.../waynergy.pid` (the PID of whichever waynergy instance it started). None of it is a secret, so unlike a plugin storing an API token, neither file is `chmod`-restricted.
- The host/port are validated (IPv4 octets, 1–65535) before being handed to `waynergy`, the reachability probe, or anything else — as literal argv elements or a character-class-restricted numeric interpolation, never as an unvalidated shell string. Nothing typed into the host field can inject a second command.
- Stopping waynergy targets the specific PID this plugin started, verifying `/proc/<pid>/comm` is still literally `waynergy` before sending `kill -TERM` — it falls back to `pkill -x waynergy` (matching **by process name, not PID**) only right after a plugin/shell reload, when that PID hasn't been read back yet.
- Desktop notifications go through `omarchy-notification-send`, the same first-party helper other Omarchy tooling uses — this plugin only ever passes it a fixed title and a message containing your own configured host:port, nothing else.
- **Auto-recovery**: if the reachability probe fails for 5 continuous seconds while waynergy is running, this plugin stops and restarts it itself (capped at 3 attempts per outage) — the same stop/start paths described above, just triggered by the plugin instead of a click. No new command surface, no elevated privileges, nothing that touches the network beyond the reachability probe already covered above.
- The only system file this plugin can modify outside its own state directory is `~/.config/hypr/bindings.lua`, and only when you explicitly set a keyboard shortcut from the panel (backed up first as `bindings.lua.bak.<timestamp>`, rolled back automatically if `hyprctl reload` reports a config error).
- Nothing runs with elevated privileges.

## Reporting a vulnerability

If you find a security issue — an injection point in how a command gets built, an
unexpected file being written or modified outside what's documented above — please report
it privately rather than opening a public issue:

**aryan@aroice.in**

Include what you found, the plugin version (`manifest.json`'s `version` field), and
reproduction steps if you have them. I'll aim to acknowledge within a few days.

Please don't open a public issue for anything that could let someone else exploit it
before a fix ships.

## Out of scope

- Vulnerabilities in waynergy itself — report those to the [waynergy project](https://github.com/r-c-f/waynergy).
- Vulnerabilities in the Omarchy shell itself, outside this plugin's own code — report those to the [Omarchy project](https://github.com/basecamp/omarchy).
