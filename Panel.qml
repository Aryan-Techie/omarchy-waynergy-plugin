import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Owns waynergy's run state (polled via pgrep), whether the waynergy binary
// is even on PATH (checked via `which`, same pattern the built-in Tailscale
// plugin uses), and the persisted host IP / label-visibility settings. The
// bar widget's right click calls toggleWaynergy() directly — no panel needed
// for that. Left click opens this panel: status, a power toggle, connection
// details, the IP field, and a switch to hide the "Waynergy" text next to
// the bar dot. Visual idiom (hero + status pill + detail grid + inline
// confirm button) matches the built-in Wi-Fi panel.
Panel {
  id: root
  moduleName: "io.github.aryan-techie.waynergy"
  ipcTarget: "io.github.aryan-techie.waynergy"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string stateDir: homeDir + "/.local/state/omarchy/io.github.aryan-techie.waynergy"
  readonly property string settingsPath: stateDir + "/settings.json"

  readonly property int port: 24800
  property string ip: "192.168.1.5"
  property string ipDraft: ip
  property string ipError: ""
  property bool running: false
  property bool showLabel: true
  property bool settingsLoaded: false

  // Optimistic true until the first `which waynergy` check lands, so the
  // panel doesn't flash "not installed" for the split second before that
  // check resolves.
  property bool installed: true
  // Set only when a start attempt's very next status check finds the
  // process gone — distinguishes "we tried and it died" from the ordinary
  // "stopped, nobody's touched it" state.
  property string lastError: ""
  property bool startPending: false

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.55)

  readonly property string statusText: running ? ("Running — connected to " + ip) : "Stopped"

  // Single status line for the pill below the hero: "not installed" always
  // wins (nothing else matters until that's fixed), then a start attempt in
  // flight, then the last start failure. Empty hides the pill entirely.
  readonly property string statusMessage: {
    if (!root.installed) return "Waynergy isn't installed or not on PATH."
    if (root.startPending) return "Starting…"
    return root.lastError
  }
  readonly property bool statusIsError: root.statusMessage !== "" && !root.startPending

  onOpenedChanged: if (root.opened) {
    root.ipDraft = root.ip
    root.ipError = ""
    root.refreshStatus()
    Qt.callLater(function() {
      if (root.opened) ipField.forceActiveFocus()
    })
  }

  // ---- Process control. Start is fire-and-forget via execDetached (not
  //      tied to this Panel's own lifetime, so reloading the plugin never
  //      kills a running session); stop/status go through pkill/pgrep on
  //      the process name since we don't track a PID across plugin reloads.
  function refreshStatus() {
    checkInstalled()
    if (statusProc.running) return
    statusProc.running = true
  }

  function checkInstalled() {
    if (whichProc.running) return
    whichProc.running = true
  }

  function startWaynergy() {
    if (root.running) return
    if (!root.installed) {
      root.lastError = "Waynergy isn't installed or not on PATH."
      return
    }
    root.lastError = ""
    root.startPending = true
    Quickshell.execDetached(["waynergy", "-c", root.ip, "-p", String(root.port), "-E"])
    root.running = true
    startCheckTimer.restart()
  }

  function stopWaynergy() {
    root.startPending = false
    root.lastError = ""
    root.running = false
    stopProc.running = true
  }

  function toggleWaynergy() {
    if (root.running) root.stopWaynergy()
    else root.startWaynergy()
  }

  function copyToClipboard(value) {
    if (!value || !root.bar) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  // ---- IP settings. Stored locally, never touches shell.json.
  function isValidIp(value) {
    var m = String(value || "").trim().match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
    if (!m) return false
    for (var i = 1; i <= 4; i++) if (Number(m[i]) > 255) return false
    return true
  }

  function saveIp() {
    var value = String(root.ipDraft || "").trim()
    if (!isValidIp(value)) {
      root.ipError = "Enter a valid IPv4 address, e.g. 192.168.1.5."
      return
    }
    root.ip = value
    root.ipDraft = value
    root.ipError = ""
    root.lastError = ""
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
    if (typeof parsed.showLabel === "boolean") root.showLabel = parsed.showLabel
    root.ipDraft = root.ip
    root.settingsLoaded = true
    refreshStatus()
  }

  function persistSettings() {
    settingsFile.setText(JSON.stringify({ ip: root.ip, showLabel: root.showLabel }, null, 2) + "\n")
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
    command: ["pgrep", "-x", "waynergy"]
    onExited: function(exitCode) {
      var isRunning = exitCode === 0
      if (!isRunning && root.startPending) {
        root.lastError = "Waynergy exited right after starting — check the IP (" + root.ip + ") and that the host is reachable."
      } else if (isRunning) {
        root.lastError = ""
      }
      root.startPending = false
      root.running = isRunning
    }
  }

  Process {
    id: stopProc
    command: ["pkill", "-x", "waynergy"]
    onExited: function() {
      Qt.callLater(root.refreshStatus)
    }
  }

  Timer {
    id: startCheckTimer
    interval: 800
    repeat: false
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: statusPollTimer
    interval: 5000
    running: root.settingsLoaded
    repeat: true
    onTriggered: root.refreshStatus()
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: ipField.activeFocus
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.toggleWaynergy()
      }

      Column {
        id: column
        width: parent.width
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
              text: root.ip
              copyable: true
              tooltipText: "Copy host IP"
            }

            DetailLabel { text: "Port" }
            DetailValue { text: String(root.port) }
          }

          RowLayout {
            width: parent.width
            spacing: Style.spacing.sm

            TextField {
              id: ipField
              Layout.fillWidth: true
              activeFocusOnTab: false
              placeholderText: "192.168.1.5"
              text: root.ipDraft
              onTextChanged: { root.ipDraft = text; root.ipError = "" }
              onAccepted: root.saveIp()
              Keys.onEscapePressed: root.close()
            }

            PanelActionButton {
              id: saveButton
              iconText: "󰄬"
              tooltipText: "Save"
              foreground: root.contentForeground
              enabled: root.ipDraft.trim() !== "" && root.ipDraft.trim() !== root.ip
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
          foreground: root.contentForeground
        }

        RowLayout {
          width: parent.width
          spacing: Style.spacing.sm

          ToggleSwitch {
            id: labelSwitch
            checked: root.showLabel
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
