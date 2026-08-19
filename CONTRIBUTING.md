# Contributing

Thanks for considering a contribution to this plugin. It's a small project — this doc is
short on purpose.

## Before you start

For anything beyond a small fix, open an issue first (or comment on an existing one) so we
can agree on the approach before you put time into it.

## Project layout

- `BarWidget.qml` — the bar pill. Thin: reads state back from `Panel.qml`, decides what the
  pill shows, and routes clicks (right-click toggles start/stop directly, left-click opens
  the panel).
- `Panel.qml` — everything else: process control (start/stop/status via `waynergy`/
  `pkill`/`pgrep`/`which` `Process`es), settings persistence, and the panel UI, all in one
  file. There's no `Model.js` — nothing here is complex enough to warrant a separate data
  model.

## Conventions worth knowing before you dig in

- **Start is detached, not tracked.** `startWaynergy()` uses `Quickshell.execDetached`, not
  a tracked `Process` object, specifically so a running waynergy session survives a plugin
  reload or shell restart. The tradeoff: we can't capture its stderr or exact exit reason —
  status is inferred from polling `pgrep -x waynergy` instead. Keep this in mind before
  "fixing" it to use a tracked `Process` — that would reintroduce the exact problem it was
  written to avoid.
- **The `which waynergy` installed-check mirrors the built-in Tailscale plugin's own
  pattern** (`$OMARCHY_PATH/shell/plugins/panels/tailscale/Service.qml`) — same idiom on
  purpose, so it stays predictable for anyone who's already read that file.
- **Settings persist to `~/.local/state/omarchy/io.github.aryan-techie.waynergy/settings.json`**
  — `{ ip, port, showLabel, keybind, recentIps }`, nothing sensitive, so no `chmod 600` step
  (unlike a plugin storing a token). Don't add anything else that writes files outside this
  without calling it out clearly in the README.
- **The panel's visual idiom borrows directly from the built-in Wi-Fi panel**
  (`$OMARCHY_PATH/shell/plugins/panels/network/Panel.qml`): the status pill for
  connecting/failed states, the Host/Port detail grid, and the inline checkmark save
  button all mirror that file's own components. Keep new UI consistent with that idiom
  rather than inventing a new one.
- **`running` (process alive) and `reachable` (TCP probe succeeded) are deliberately
  separate properties.** Don't collapse them into one — the entire point of `reachable` is
  catching the case where the process is alive but the connection isn't, which `running`
  alone can never see.
- **Host/port validation happens once, in `parseHostPort()`.** Every other function that
  needs a host or port (start, the reachability probe, Known Hosts) goes through it or
  trusts `root.ip`/`root.port` after it's already run — don't re-validate or re-parse
  ad hoc elsewhere.
- **Notifications (`notify()`, wrapping `omarchy-notification-send`) fire once per
  transition, not once per poll.** If you add a new notification, gate it the same way
  the existing two are (compare against the previous state, not just the current one) or
  it'll spam on every 5-second poll while the bad state persists.

## Making a change

1. Edit the files in your checkout.
2. `omarchy plugin validate .` — the reliable structural check; `qmllint` doesn't resolve
   this shell's runtime-only `qs.*` namespaces outside a live install, so don't rely on its
   exit code alone.
3. Copy your checkout to `~/.config/omarchy/plugins/io.github.aryan-techie.waynergy/` for
   live testing (`omarchy plugin validate` rejects symlinked plugin folders, so copy rather
   than symlink).
4. Saved changes under `~/.config/omarchy/plugins/` are *supposed* to hot-reload via
   `omarchy-shell shell rescanPlugins` — but Quickshell's own compiled-QML disk cache
   (`~/.cache/quickshell/qmlcache`) can serve a stale version even after a plugin reload
   logs successfully. If a change isn't showing up, don't trust the rescan: `rm -rf
   ~/.cache/quickshell/qmlcache && omarchy restart shell` for a real, verified-clean load.
5. Check `qs log -p "$OMARCHY_PATH/shell" --tail 100` for new warnings or errors.
6. Test against a real waynergy setup — a clean log only proves it loaded, not that
   start/stop/IP-change actually works.

## Submitting a PR

- Keep PRs focused — one change, one PR, easier to review.
- Update the README if you change anything user-facing (a click mapping, a setting, what
  the panel shows).

## Reporting bugs / requesting features

Open an issue with the plugin version (`manifest.json`'s `version` field), what you
expected vs. what happened, and `qs log` output if it's a crash or a silent failure.

## Security

Found a security issue? See [SECURITY.md](SECURITY.md) rather than opening a public issue.
