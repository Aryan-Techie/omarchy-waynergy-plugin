import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar entry point: a status pill for waynergy. Right click starts/stops the
// process; left click opens the panel (status, power toggle, IP field). All
// process and settings state lives in Panel.qml — this file only reads it
// back to decide what the pill shows.
BarWidget {
  id: root
  moduleName: "io.github.aryan-techie.waynergy"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refreshStatus() {
    if (panelLoader.item && panelLoader.item.refreshStatus) panelLoader.item.refreshStatus()
  }

  // ---- Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on this root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function toggleWaynergy() {
    if (panelLoader.item) panelLoader.item.toggleWaynergy()
  }

  readonly property bool running: panelLoader.item ? panelLoader.item.running === true : false
  readonly property bool installed: panelLoader.item ? panelLoader.item.installed !== false : true
  readonly property bool showLabel: panelLoader.item ? panelLoader.item.showLabel !== false : true
  readonly property string displayLabel: {
    var dot = root.running ? "●" : "○"
    return root.showLabel ? (dot + " Waynergy") : dot
  }

  function injectPanelAndRefresh() {
    injectPanel()
    root.refreshStatus()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanelAndRefresh)
    }
  }

  IpcHandler {
    target: "io.github.aryan-techie.waynergy"

    function refresh(): void { root.broadcast("refreshStatus") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function start(): void { if (root.running) return; root.broadcast("toggleWaynergy") }
    function stop(): void { if (!root.running) return; root.broadcast("toggleWaynergy") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayLabel
    tooltipText: !root.installed
      ? "Waynergy not installed — left-click for details"
      : (root.running
        ? "Waynergy running — right-click to stop, left-click for settings"
        : "Waynergy stopped — right-click to start, left-click for settings")
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleWaynergy()
      else if (b === Qt.MiddleButton) root.refreshStatus()
      else root.togglePanel()
    }
  }
}
