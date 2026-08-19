import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Owns waynergy's run state — polled against the specific PID this plugin
// launched when known, `pgrep -x waynergy` as a fallback right after a
// reload — whether the waynergy binary is even on PATH (checked via
// `which`, same pattern the built-in Tailscale plugin uses), the persisted
// host IP / label-visibility / keybind settings, and keyboard-cursor
// navigation between the panel's controls. The bar widget's right click
// calls toggleWaynergy() directly — no panel needed for that. Left click
// (or the global shortcut below) opens this panel: status, a power toggle,
// connection details, the IP field, a label-visibility switch, and a
// keyboard-shortcut recorder. Visual idiom (hero + status pill + detail
// grid + inline confirm button, rotating hero status phrases) matches the
// built-in Wi-Fi/Bluetooth panels; the keyboard-shortcut recorder matches
// the one in the todoist plugin.
Panel {
  id: root
  moduleName: "io.github.aryan-techie.waynergy"
  ipcTarget: "io.github.aryan-techie.waynergy"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string pluginDir: homeDir + "/.config/omarchy/plugins/io.github.aryan-techie.waynergy"
  readonly property string stateDir: homeDir + "/.local/state/omarchy/io.github.aryan-techie.waynergy"
  readonly property string settingsPath: stateDir + "/settings.json"
  readonly property string pidPath: stateDir + "/waynergy.pid"

  // The PID of the specific waynergy instance this plugin started, so
  // stop/status target that process instead of "whatever's named
  // waynergy" — see startWaynergy()/pidCommentCheck(). Not persisted: a
  // stale PID surviving a reboot could get reused by an unrelated
  // process, which would be actively dangerous to act on. Resets to 0 on
  // stop and after every plugin/shell reload; self-heals back to a real
  // value on the next status poll if exactly one waynergy process is
  // found (see statusProc.onExited).
  property int trackedPid: 0

  readonly property int defaultPort: 24800
  property string ip: "192.168.1.5"
  property int port: defaultPort
  property string ipDraft: ip
  property string ipError: ""
  property bool running: false
  property bool showLabel: true
  property bool settingsLoaded: false

  // "192.168.1.5" when on the default port, "192.168.1.5:9999" otherwise —
  // the one canonical string used for display, Known Hosts entries, and
  // round-tripping through the IP field.
  readonly property string hostDisplay: root.port === root.defaultPort ? root.ip : (root.ip + ":" + root.port)

  // Tri-state (null = not checked yet / not running): whether the last TCP
  // probe to host:port while running actually got through. Separate from
  // `running`, which only means the local process is alive — the real gap
  // that was missing before: a live process can still be talking to
  // nothing if the other side dropped off the network.
  property var reachable: null
  // Auto-recovery attempts made for the *current* unreachable episode —
  // capped so a genuinely dead host doesn't get restarted forever. Reset
  // on a real recovery (see reachProc) and on any manually-triggered
  // start (see toggleWaynergy()), but deliberately NOT inside
  // stopWaynergy()/startWaynergy() themselves, since recoveryTimer calls
  // those directly as part of counting an attempt.
  property int recoveryAttempts: 0

  // Optimistic true until the first `which waynergy` check lands, so the
  // panel doesn't flash "not installed" for the split second before that
  // check resolves.
  property bool installed: true
  // Set only when a start attempt's very next status check finds the
  // process gone — distinguishes "we tried and it died" from the ordinary
  // "stopped, nobody's touched it" state.
  property string lastError: ""
  property bool startPending: false

  // ---- Live uptime stat. Not persisted — stamped on start, cleared on
  //      stop, and (for "was already running when the plugin loaded")
  //      stamped the first time a status poll confirms it without one.
  property double runningSinceMs: 0
  property int uptimeTick: 0

  // ---- Known hosts: last few saved IPs, for one-click switching (the
  //      direct analog of the built-in Wi-Fi panel's Known Networks list).
  property var recentIps: []

  // ---- Keyboard shortcut (mirrors the todoist plugin's recorder exactly).
  property string keybindCombo: ""
  property bool recordingKeybind: false
  property string pendingKeybindCombo: ""
  property string keybindRecordError: ""
  property string keybindApplyStatus: ""
  property string keybindApplyError: ""

  // ---- Keyboard cursor navigation between the panel's own controls.
  property bool cursorActive: false
  property string focusSection: "power"

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.55)

  // Rotating hero phrases while actually connected — same idiom as the
  // built-in Wi-Fi ("Counting collisions") and Bluetooth ("Herding
  // headsets") panels: PanelHero's metaOpacity fades out, phraseIndex
  // advances, fades back in, on a timer that only runs while it's worth
  // animating. Falls back to a plain state word the rest of the time.
  property int phraseIndex: 0
  readonly property var activePhrases: [
    "Sharing keystrokes",
    "Herding cursors",
    "Passing the mouse",
    "Bridging desktops",
    "Syncing clipboards",
    "Crossing the wire",
    "Mirroring input",
    "Routing keypresses"
  ]
  readonly property bool rotatingPhrases: root.running && root.reachable !== false
  readonly property string statusText: {
    if (!root.installed) return "Not installed"
    if (root.startPending) return "Starting…"
    if (!root.running) return "Stopped"
    if (root.reachable === false) return "Not responding"
    return root.activePhrases[root.phraseIndex % root.activePhrases.length]
  }

  // Single status line for the pill below the hero: "not installed" always
  // wins (nothing else matters until that's fixed), then a start attempt in
  // flight, then an unreachable-while-running host, then the last error.
  // Empty hides the pill entirely.
  readonly property string statusMessage: {
    if (!root.installed) return "Waynergy isn't installed or not on PATH."
    if (root.startPending) return "Starting…"
    if (root.running && root.reachable === false) return "Running, but " + root.hostDisplay + " isn't responding."
    return root.lastError
  }
  readonly property bool statusIsError: root.statusMessage !== "" && !root.startPending

  readonly property string uptimeText: {
    root.uptimeTick // referenced only to force re-evaluation once a second
    if (!root.running || root.runningSinceMs === 0) return "--"
    var secs = Math.max(0, Math.floor((Date.now() - root.runningSinceMs) / 1000))
    var m = Math.floor(secs / 60)
    var s = secs % 60
    return m + "m " + (s < 10 ? "0" : "") + s + "s"
  }

  onOpenedChanged: if (root.opened) {
    root.ipDraft = root.hostDisplay
    root.ipError = ""
    root.cursorActive = false
    root.focusSection = "power"
    root.refreshStatus()
  }

  // ---- Process control. Start is fire-and-forget via execDetached (not
  //      tied to this Panel's own lifetime, so reloading the plugin never
  //      kills a running session). Stop/status target the specific PID
  //      this plugin launched when known (see startWaynergy()), falling
  //      back to matching by process name only when it isn't — right
  //      after a plugin/shell reload, where in-memory state is lost.
  function refreshStatus() {
    checkInstalled()
    if (statusProc.running) return
    statusProc.command = root.trackedPid > 0
      ? ["bash", "-c", root.pidCommentCheck(root.trackedPid)]
      : ["pgrep", "-x", "waynergy"]
    statusProc.running = true
  }

  function checkInstalled() {
    if (whichProc.running) return
    whichProc.running = true
  }

  // TCP reachability probe — the actual gap `running` alone can't cover:
  // the local process can stay alive while the other side has dropped off
  // the network. `root.ip`/`root.port` are already validated (digits/dots,
  // 1-65535) by the time this runs, so interpolating them into the bash
  // command below carries no injection risk.
  function checkReachable() {
    if (reachProc.running) return
    reachProc.command = ["bash", "-c", "timeout 2 bash -c 'echo > /dev/tcp/" + root.ip + "/" + root.port + "' 2>/dev/null"]
    reachProc.running = true
  }

  // `[ "$(cat /proc/<pid>/comm)" = waynergy ]` — true only when that PID
  // is both alive *and* still actually waynergy, closing the PID-reuse
  // race a bare `kill -0`/by-name match can't: if the process this
  // plugin started already exited and the PID got recycled by something
  // else entirely, this correctly reports "not ours" instead of "alive".
  function pidCommentCheck(pid) {
    return "[ \"$(cat /proc/" + pid + "/comm 2>/dev/null)\" = waynergy ]"
  }

  function startWaynergy() {
    if (root.running) return
    if (!root.installed) {
      root.lastError = "Waynergy isn't installed or not on PATH."
      return
    }
    root.lastError = ""
    root.startPending = true
    root.trackedPid = 0
    // Launched through a detached wrapper (not a tracked Process, which
    // Quickshell would kill on plugin/shell reload) that backgrounds
    // waynergy, records its real PID via `$!`, then exits — the
    // backgrounded child is orphaned and reparented normally when the
    // wrapper exits, same as any ordinary background job, so it keeps
    // running exactly like the old direct execDetached call did.
    Quickshell.execDetached(["bash", "-c",
      "waynergy -c " + Util.shellQuote(root.ip) + " -p " + root.port + " -E >/dev/null 2>&1 & echo $! > " + Util.shellQuote(root.pidPath) + "; disown"])
    root.running = true
    root.runningSinceMs = Date.now()
    startCheckTimer.restart()
  }

  function readTrackedPid() {
    if (pidReadProc.running) return
    pidReadProc.running = true
  }

  function stopWaynergy() {
    root.startPending = false
    root.lastError = ""
    root.running = false
    root.runningSinceMs = 0
    root.reachable = null
    if (root.trackedPid > 0) {
      stopProc.command = ["bash", "-c", root.pidCommentCheck(root.trackedPid) + " && kill -TERM " + root.trackedPid]
    } else {
      stopProc.command = ["pkill", "-x", "waynergy"]
    }
    root.trackedPid = 0
    stopProc.running = true
  }

  function toggleWaynergy() {
    if (root.running) {
      root.stopWaynergy()
    } else {
      root.recoveryAttempts = 0
      root.startWaynergy()
    }
  }

  function copyToClipboard(value) {
    if (!value || !root.bar) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  function notify(title, body) {
    Quickshell.execDetached(["omarchy-notification-send", title, body, "--app-name", "Waynergy", "-u", "critical"])
  }

  // ---- Host settings. Stored locally, never touches shell.json. Accepts
  //      "ip" or "ip:port" — port defaults to 24800 when omitted.
  function isValidIp(value) {
    var m = String(value || "").trim().match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
    if (!m) return false
    for (var i = 1; i <= 4; i++) if (Number(m[i]) > 255) return false
    return true
  }

  function isValidPort(value) {
    var n = Number(value)
    return isFinite(n) && n === Math.floor(n) && n >= 1 && n <= 65535
  }

  // Parses "ip" or "ip:port" into { ip, port, valid }. No colon means the
  // whole string is the IP and port falls back to the default.
  function parseHostPort(value) {
    var raw = String(value || "").trim()
    var colonIndex = raw.lastIndexOf(":")
    if (colonIndex === -1) return { ip: raw, port: root.defaultPort, valid: isValidIp(raw) }
    var ipPart = raw.substring(0, colonIndex)
    var portPart = raw.substring(colonIndex + 1)
    var portValid = /^\d+$/.test(portPart) && isValidPort(portPart)
    return { ip: ipPart, port: portValid ? Number(portPart) : 0, valid: isValidIp(ipPart) && portValid }
  }

  function saveIp() {
    var parsed = parseHostPort(root.ipDraft)
    if (!parsed.valid) {
      root.ipError = "Enter a valid IPv4 address, optionally with :port — e.g. 192.168.1.5 or 192.168.1.5:9999."
      return
    }
    root.ip = parsed.ip
    root.port = parsed.port
    root.ipDraft = root.hostDisplay
    root.ipError = ""
    root.lastError = ""
    rememberIp(root.hostDisplay)
    persistSettings()
  }

  // Push-to-front, dedupe, cap-5 — same idiom the built-in Tailscale panel
  // uses for its recent Mullvad regions.
  function rememberIp(value) {
    var next = [value]
    for (var i = 0; i < root.recentIps.length && next.length < 5; i++) {
      var existing = root.recentIps[i]
      if (existing !== value && next.indexOf(existing) === -1) next.push(existing)
    }
    root.recentIps = next
  }

  // Switching a known host updates the target for the *next* start — an
  // already-running session is left alone rather than silently restarted.
  function switchToIp(value) {
    var parsed = parseHostPort(value)
    if (!parsed.valid) return
    root.ip = parsed.ip
    root.port = parsed.port
    root.ipDraft = root.hostDisplay
    root.ipError = ""
    root.lastError = ""
    rememberIp(root.hostDisplay)
    persistSettings()
  }

  function forgetIp(value) {
    root.recentIps = root.recentIps.filter(function(v) { return v !== value })
    persistSettings()
  }

  function setShowLabel(value) {
    root.showLabel = value === true
    persistSettings()
  }

  function ensureStateDir() {
    mkdirProc.running = true
  }

  function loadSettingsFromText(text) {
    var parsed = {}
    try { parsed = JSON.parse(text || "{}") } catch (e) { parsed = {} }
    if (typeof parsed.ip === "string" && isValidIp(parsed.ip)) root.ip = String(parsed.ip).trim()
    if (typeof parsed.port === "number" && isValidPort(parsed.port)) root.port = Math.round(parsed.port)
    if (typeof parsed.showLabel === "boolean") root.showLabel = parsed.showLabel
    if (typeof parsed.keybind === "string") root.keybindCombo = parsed.keybind
    if (Array.isArray(parsed.recentIps)) {
      var loaded = []
      for (var i = 0; i < parsed.recentIps.length && loaded.length < 5; i++) {
        var candidate = String(parsed.recentIps[i] || "").trim()
        if (parseHostPort(candidate).valid && loaded.indexOf(candidate) === -1) loaded.push(candidate)
      }
      root.recentIps = loaded
    }
    root.ipDraft = root.hostDisplay
    root.settingsLoaded = true
    refreshStatus()
  }

  function persistSettings() {
    settingsFile.setText(JSON.stringify({ ip: root.ip, port: root.port, showLabel: root.showLabel, keybind: root.keybindCombo, recentIps: root.recentIps }, null, 2) + "\n")
  }

  // ---- Keyboard shortcut recording. Mirrors a stripped-down Hyprland key
  //      combo into "MOD + MOD + KEY" form; set-keybind.sh does the actual
  //      ~/.config/hypr/bindings.lua edit (backup + reload + auto-rollback).
  function isBareModifier(key) {
    return key === Qt.Key_Super_L || key === Qt.Key_Super_R || key === Qt.Key_Meta
      || key === Qt.Key_Control || key === Qt.Key_Shift || key === Qt.Key_Alt || key === Qt.Key_AltGr
  }

  function hyprKeyName(key) {
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    if (key >= Qt.Key_F1 && key <= Qt.Key_F12) return "F" + (key - Qt.Key_F1 + 1)
    var names = {}
    names[Qt.Key_Space] = "SPACE"
    names[Qt.Key_Return] = "RETURN"
    names[Qt.Key_Enter] = "RETURN"
    names[Qt.Key_Tab] = "TAB"
    names[Qt.Key_Backspace] = "BACKSPACE"
    names[Qt.Key_Comma] = "comma"
    names[Qt.Key_Period] = "period"
    names[Qt.Key_Minus] = "minus"
    names[Qt.Key_Equal] = "equal"
    names[Qt.Key_Slash] = "slash"
    return names[key] || ""
  }

  function startRecordingKeybind() {
    root.recordingKeybind = true
    root.pendingKeybindCombo = ""
    root.keybindRecordError = ""
    root.keybindApplyStatus = ""
  }

  function cancelRecordingKeybind() {
    root.recordingKeybind = false
    root.pendingKeybindCombo = ""
    root.keybindRecordError = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function handleKeybindRecordKey(event) {
    if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) {
      root.cancelRecordingKeybind()
      event.accepted = true
      return
    }
    if (root.isBareModifier(event.key)) { event.accepted = true; return }

    var mods = []
    if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
    if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
    if (event.modifiers & Qt.AltModifier) mods.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")

    var keyStr = root.hyprKeyName(event.key)
    if (keyStr === "") {
      root.keybindRecordError = "Unsupported key — try a letter, digit, F-key, or punctuation key."
      event.accepted = true
      return
    }
    if (mods.length === 0) {
      root.keybindRecordError = "Add a modifier (Super/Ctrl/Alt/Shift) — a bare key would break typing everywhere."
      event.accepted = true
      return
    }

    root.keybindRecordError = ""
    root.pendingKeybindCombo = mods.join(" + ") + " + " + keyStr
    event.accepted = true
  }

  function applyKeybindCombo(combo) {
    if (combo === "" || root.keybindApplyStatus === "applying") return
    root.keybindApplyStatus = "applying"
    root.keybindApplyError = ""
    keybindProc.pendingApply = combo
    keybindProc.command = ["bash", root.pluginDir + "/set-keybind.sh", combo]
    keybindProc.running = true
  }

  function removeKeybindCombo() {
    if (root.keybindCombo === "" || root.keybindApplyStatus === "applying") return
    root.keybindApplyStatus = "applying"
    root.keybindApplyError = ""
    keybindProc.pendingApply = ""
    keybindProc.command = ["bash", root.pluginDir + "/set-keybind.sh", "__REMOVE__"]
    keybindProc.running = true
  }

  // ---- Keyboard cursor navigation. Up/Down (arrows or j/k, via
  //      PanelKeyCatcher) move a highlight between every focusable control;
  //      Space/Enter activates whichever one it's on. Order matches the
  //      panel's visual top-to-bottom layout, filtered down to whatever's
  //      actually visible right now (the keybind row swaps Default/Record/
  //      Remove for nothing at all once recording takes over the whole
  //      panel via PanelKeyCatcher.blocked).
  function currentFocusOrder() {
    var order = ["power", "ip", "save"]
    for (var i = 0; i < root.recentIps.length; i++) order.push("knownIp" + i)
    order.push("label", "keybindDefault", "keybindRecord")
    if (root.keybindCombo !== "") order.push("keybindRemove")
    return order
  }

  function moveCursor(delta) {
    root.cursorActive = true
    var order = root.currentFocusOrder()
    var idx = order.indexOf(root.focusSection)
    idx = idx === -1 ? 0 : Math.max(0, Math.min(order.length - 1, idx + delta))
    root.focusSection = order[idx]
  }

  function activateCursor() {
    root.cursorActive = true
    if (root.focusSection === "power") root.toggleWaynergy()
    else if (root.focusSection === "ip") Qt.callLater(function() { ipField.forceActiveFocus(); ipField.selectAll() })
    else if (root.focusSection === "save") { if (saveButton.enabled) root.saveIp() }
    else if (root.focusSection === "label") root.setShowLabel(!root.showLabel)
    else if (root.focusSection === "keybindDefault") { if (keybindDefaultButton.enabled) root.applyKeybindCombo("CTRL + SUPER + Y") }
    else if (root.focusSection === "keybindRecord") { if (keybindRecordButton.enabled) root.startRecordingKeybind() }
    else if (root.focusSection === "keybindRemove") { if (keybindRemoveButton.visible && keybindRemoveButton.enabled) root.removeKeybindCombo() }
    else if (root.focusSection.indexOf("knownIp") === 0) {
      var idx = parseInt(root.focusSection.substring(7), 10)
      if (idx >= 0 && idx < root.recentIps.length) root.switchToIp(root.recentIps[idx])
    }
  }

  Component.onCompleted: {
    ensureStateDir()
    checkInstalled()
    Qt.callLater(function() { settingsFile.reload() })
  }

  // ---- Processes -------------------------------------------------------

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
  }

  Process {
    id: whichProc
    running: false
    command: ["which", "waynergy"]
    onExited: function(exitCode) {
      root.installed = exitCode === 0
    }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var isRunning = exitCode === 0
      var wasRunning = root.running
      // Self-heal after a reload: if we weren't tracking a PID (so this
      // check ran the `pgrep -x` fallback) and it found exactly one
      // match, adopt it — stop/status become PID-precise again from
      // here on. More than one match stays deliberately ambiguous.
      if (root.trackedPid === 0 && isRunning) {
        var lines = String(statusOut.text || "").trim().split("\n").filter(function(l) { return l !== "" })
        if (lines.length === 1) {
          var found = parseInt(lines[0], 10)
          if (!isNaN(found) && found > 0) root.trackedPid = found
        }
      }
      if (!isRunning && root.startPending) {
        root.lastError = "Waynergy exited right after starting — check the IP (" + root.hostDisplay + ") and that the host is reachable."
      } else if (isRunning) {
        root.lastError = ""
        if (root.runningSinceMs === 0) root.runningSinceMs = Date.now()
        root.checkReachable()
      } else {
        root.runningSinceMs = 0
        root.reachable = null
        root.trackedPid = 0
        // Discovered by a routine poll, not a stop we asked for ourselves
        // (stopWaynergy() already flips `running` false synchronously, so
        // wasRunning only reads true here when nothing touched it — the
        // actual "it just died" case).
        if (wasRunning && !root.startPending) {
          root.lastError = "Waynergy stopped unexpectedly — it was running a moment ago."
          root.notify("Waynergy stopped", "Lost connection to " + root.hostDisplay + ".")
        }
      }
      root.startPending = false
      root.running = isRunning
    }
  }

  Process {
    id: pidReadProc
    command: ["cat", root.pidPath]
    stdout: StdioCollector {
      id: pidReadOut
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text || "").trim(), 10)
        if (!isNaN(n) && n > 0) root.trackedPid = n
      }
    }
  }

  Process {
    id: reachProc
    onExited: function(exitCode) {
      var wasReachable = root.reachable
      root.reachable = exitCode === 0
      if (root.reachable) {
        root.recoveryAttempts = 0
        recoveryTimer.stop()
      } else if (wasReachable !== false) {
        root.notify("Waynergy unreachable", "Running, but " + root.hostDisplay + " isn't responding.")
        if (root.recoveryAttempts < 3) recoveryTimer.restart()
      }
    }
  }

  Process {
    id: stopProc
    onExited: function() {
      Qt.callLater(root.refreshStatus)
    }
  }

  Process {
    id: keybindProc
    property string pendingApply: ""
    stderr: StdioCollector {
      id: keybindErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.keybindCombo = keybindProc.pendingApply
        root.keybindApplyStatus = ""
        root.keybindApplyError = ""
        root.recordingKeybind = false
        root.pendingKeybindCombo = ""
        persistSettings()
      } else {
        root.keybindApplyStatus = "error"
        root.keybindApplyError = (keybindErr.text || "").trim() || "Failed to apply keybind."
      }
    }
  }

  Timer {
    id: startCheckTimer
    interval: 800
    repeat: false
    onTriggered: {
      root.readTrackedPid()
      root.refreshStatus()
    }
  }

  // Debounced auto-recovery for a stuck key: waynergy's virtual input
  // device keeps reporting whatever key was down when the connection
  // died until something closes its file descriptor, which is what a
  // clean stop+restart does (same reason touching the desktop's own
  // physical mouse/keyboard clears it — a fresh input event supersedes
  // the stuck one; this just triggers that release in software instead).
  // Waits out a single failed probe first — a network blip isn't worth
  // restarting over, and restarting is itself a disconnect from
  // waynergy's side, so acting on every blip would work against the
  // point. Cancelled by reachProc the moment reachability recovers.
  Timer {
    id: recoveryTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (!root.running || root.reachable !== false) return
      root.recoveryAttempts++
      root.notify("Waynergy reconnecting", root.hostDisplay + " stopped responding — restarting waynergy (attempt " + root.recoveryAttempts + " of 3).")
      root.stopWaynergy()
      Qt.callLater(root.startWaynergy)
    }
  }

  Timer {
    id: statusPollTimer
    interval: 5000
    running: root.settingsLoaded
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: uptimeTimer
    interval: 1000
    running: root.running && root.runningSinceMs > 0
    repeat: true
    onTriggered: root.uptimeTick++
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        hero.metaOpacity = 1.0
      }
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettingsFromText(text())
    onLoadFailed: root.loadSettingsFromText("")
  }

  // ---- Chrome ------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      clip: true
      blocked: ipField.activeFocus || root.recordingKeybind
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.activateCursor()
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.toggleWaynergy()
        else if (t === "r" || t === "R") root.refreshStatus()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.spacing.lg

          PanelHero {
            id: hero
            width: parent.width
            title: "Waynergy"
            meta: root.statusText
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            iconOpacity: root.running ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                text: "⏻"
                color: root.running ? root.contentForeground : root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                checked: root.running
                interactive: root.installed
                hasCursor: root.cursorActive && root.focusSection === "power"
                foreground: hero.foreground
                onToggled: root.toggleWaynergy()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: root.installed ? (root.running ? "Stop waynergy" : "Start waynergy") : "Waynergy isn't installed"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          BorderSurface {
            id: statusPill
            visible: root.statusMessage !== ""
            width: parent.width
            height: Math.max(Style.spacing.controlHeight, statusPillText.implicitHeight + Style.spacing.sm * 2)
            color: Style.normalFillFor(root.contentForeground)
            borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)
            radius: Style.cornerRadius

            Text {
              id: statusPillText
              anchors.fill: parent
              anchors.margins: Style.spacing.sm
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              wrapMode: Text.WordWrap
              text: root.statusMessage
              color: root.statusIsError ? Color.urgent : root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          Column {
            width: parent.width
            spacing: Style.spacing.sm

            PanelSectionHeader {
              text: "CONNECTION"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            GridLayout {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(20)
              rowSpacing: Style.spacing.labelGap

              DetailLabel { text: "Host" }
              DetailValue {
                text: root.hostDisplay
                copyable: true
                tooltipText: "Copy host"
              }

              DetailLabel { text: "Uptime" }
              DetailValue { text: root.uptimeText }

              DetailLabel { text: "Port" }
              DetailValue { text: String(root.port) }
            }

            Text {
              width: parent.width
              text: "IP of the PC running the waynergy/Synergy server. Add :port to override the default (" + root.defaultPort + ")."
              wrapMode: Text.WordWrap
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            RowLayout {
              width: parent.width
              spacing: Style.spacing.sm

              TextField {
                id: ipField
                Layout.fillWidth: true
                activeFocusOnTab: false
                hasCursor: root.cursorActive && root.focusSection === "ip" && !ipField.activeFocus
                horizontalPadding: Style.spacing.controlPaddingX + Style.space(4)
                verticalPadding: Style.spacing.inputPaddingY + Style.space(5)
                placeholderText: "192.168.1.5 or 192.168.1.5:9999"
                text: root.ipDraft
                onTextChanged: { root.ipDraft = text; root.ipError = "" }
                onAccepted: root.saveIp()
                Keys.onEscapePressed: {
                  ipField.focus = false
                  root.cursorActive = true
                  root.focusSection = "ip"
                  Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                }
              }

              PanelActionButton {
                id: saveButton
                iconText: "󰄬"
                tooltipText: "Save"
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "save"
                enabled: root.ipDraft.trim() !== "" && root.ipDraft.trim() !== root.hostDisplay
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.saveIp()
              }
            }

            Text {
              visible: root.ipError !== ""
              width: parent.width
              text: root.ipError
              color: Color.urgent
              wrapMode: Text.WordWrap
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSeparator {
            visible: root.recentIps.length > 0
            foreground: root.contentForeground
          }

          Column {
            visible: root.recentIps.length > 0
            width: parent.width
            spacing: Style.spacing.sm

            PanelSectionHeader {
              text: "KNOWN HOSTS"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.recentIps
                KnownHostRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  hostIp: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          RowLayout {
            width: parent.width
            spacing: Style.spacing.sm

            ToggleSwitch {
              id: labelSwitch
              checked: root.showLabel
              hasCursor: root.cursorActive && root.focusSection === "label"
              foreground: root.contentForeground
              Layout.alignment: Qt.AlignVCenter
              onToggled: root.setShowLabel(!root.showLabel)
            }

            Text {
              text: "Show \"Waynergy\" label in the bar"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
            }
          }

          PanelSeparator {
            foreground: root.contentForeground
          }

          Column {
            width: parent.width
            spacing: Style.spacing.sm

            PanelSectionHeader {
              text: "KEYBOARD SHORTCUT"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Text {
              width: parent.width
              text: root.keybindCombo !== "" ? ("Current: " + root.keybindCombo) : "No shortcut set."
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Flow {
              visible: !root.recordingKeybind
              width: parent.width
              spacing: Style.spacing.sm

              Button {
                id: keybindDefaultButton
                text: "Ctrl+Super+Y"
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "keybindDefault"
                selected: root.keybindCombo === "CTRL + SUPER + Y"
                enabled: root.keybindApplyStatus !== "applying" && root.keybindCombo !== "CTRL + SUPER + Y"
                onClicked: root.applyKeybindCombo("CTRL + SUPER + Y")
              }

              Button {
                id: keybindRecordButton
                text: "Record custom…"
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "keybindRecord"
                enabled: root.keybindApplyStatus !== "applying"
                onClicked: root.startRecordingKeybind()
              }

              Button {
                id: keybindRemoveButton
                text: "Remove"
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "keybindRemove"
                visible: root.keybindCombo !== ""
                enabled: root.keybindApplyStatus !== "applying"
                onClicked: root.removeKeybindCombo()
              }
            }

            Column {
              visible: root.recordingKeybind
              width: parent.width
              spacing: Style.spacing.xs

              Rectangle {
                width: parent.width
                height: Style.spacing.controlHeight + Style.spacing.sm * 2
                radius: Style.cornerRadius
                color: Style.hoverFillFor(root.contentForeground, Color.accent)
                border.width: 1
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.4)

                Text {
                  anchors.centerIn: parent
                  text: root.pendingKeybindCombo !== "" ? root.pendingKeybindCombo : "Press a shortcut…"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                }

                Item {
                  id: keybindRecorder
                  anchors.fill: parent
                  focus: root.recordingKeybind
                  Keys.onPressed: function(event) { root.handleKeybindRecordKey(event) }
                }
              }

              Text {
                width: parent.width
                text: root.keybindRecordError !== "" ? root.keybindRecordError : "Hold your modifiers and press a key. Esc cancels."
                color: root.keybindRecordError !== "" ? Color.urgent : Qt.darker(root.contentForeground, 1.4)
                wrapMode: Text.WordWrap
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Flow {
                width: parent.width
                spacing: Style.spacing.sm

                Button {
                  text: "Apply"
                  foreground: root.contentForeground
                  enabled: root.pendingKeybindCombo !== "" && root.keybindApplyStatus !== "applying"
                  onClicked: root.applyKeybindCombo(root.pendingKeybindCombo)
                }

                Button {
                  text: "Cancel"
                  foreground: root.contentForeground
                  onClicked: root.cancelRecordingKeybind()
                }
              }
            }

            Text {
              visible: root.keybindApplyStatus === "error"
              width: parent.width
              text: root.keybindApplyError
              color: Color.urgent
              wrapMode: Text.WordWrap
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }

  component KnownHostRow: CursorSurface {
    id: hostRow
    property string hostIp: ""
    property int rowIndex: 0
    readonly property bool active: hostRow.hostIp === root.hostDisplay

    hasCursor: root.cursorActive && root.focusSection === ("knownIp" + hostRow.rowIndex)
    current: hostRow.active
    foreground: root.contentForeground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    // Declared before rowContent so it sits underneath in stacking order —
    // the PanelActionButton inside rowContent needs to receive its own
    // clicks rather than have this row-wide area steal them (matches the
    // built-in Tailscale panel's PeerRow: its hover MouseArea sits under
    // the row's own action buttons the same way).
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "knownIp" + hostRow.rowIndex }
      onClicked: root.switchToIp(hostRow.hostIp)
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: hostRow.active && root.running ? "●" : "○"
        color: hostRow.active ? root.contentForeground : root.dim
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        Text {
          Layout.fillWidth: true
          text: hostRow.hostIp
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          visible: hostRow.active
          text: root.running ? "Running" : "Active"
          color: Qt.darker(root.contentForeground, 1.4)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }

      PanelActionButton {
        iconText: "✕"
        tooltipText: "Forget"
        foreground: root.contentForeground
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.forgetIp(hostRow.hostIp)
      }
    }
  }

  component DetailLabel: Text {
    color: root.contentForeground
    opacity: 0.6
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component DetailValue: Text {
    property bool copyable: false
    property string tooltipText: "Copy to clipboard"

    Layout.fillWidth: true
    horizontalAlignment: Text.AlignRight
    color: root.contentForeground
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight

    MouseArea {
      id: valueMouse
      anchors.fill: parent
      enabled: parent.copyable && parent.text !== ""
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.copyToClipboard(parent.text)
    }

    PanelToolTip {
      visible: valueMouse.enabled && valueMouse.containsMouse
      text: parent.tooltipText
      fontFamily: root.contentFontFamily
    }
  }
}
