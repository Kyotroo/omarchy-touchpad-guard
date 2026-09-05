import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "kdm.touchpad-guard"

  property var guardStatus: Model.normalizeStatus("")
  property var commandQueue: []
  property var activeRequest: null
  property string controllerStdout: ""
  property string controllerStderr: ""
  property bool busy: false

  readonly property string controllerPath: {
    var url = String(Qt.resolvedUrl("bin/touchpad-guard"))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    return decodeURIComponent(url)
  }

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function requestQueued(command) {
    if (activeRequest && activeRequest.command === command) return true
    for (var i = 0; i < commandQueue.length; i++)
      if (commandQueue[i].command === command) return true
    return false
  }

  function enqueue(args, mutation) {
    var request = { command: String(args[0]), args: args, mutation: mutation === true }
    var next = commandQueue.slice()
    next.push(request)
    commandQueue = next
    busy = true
    startNext()
  }

  function startNext() {
    if (activeRequest || controllerProc.running || commandQueue.length === 0) return
    var next = commandQueue.slice()
    activeRequest = next.shift()
    commandQueue = next
    controllerStdout = ""
    controllerStderr = ""
    controllerProc.command = [controllerPath].concat(activeRequest.args)
    controllerProc.running = true
  }

  function finishRequest(exitCode) {
    var request = activeRequest
    activeRequest = null
    var parsed = Model.normalizeStatus(controllerStdout)
    if (exitCode !== 0 && parsed.ok) {
      parsed = Model.normalizeStatus(JSON.stringify({
        schemaVersion: 1,
        ok: false,
        error: controllerStderr || "Touchpad controller failed"
      }))
    }
    guardStatus = parsed

    if (request && request.mutation) root.broadcast("refresh")
    if (commandQueue.length > 0) Qt.callLater(root.startNext)
    else busy = false
  }

  function refresh() {
    if (!requestQueued("status")) enqueue(["status"], false)
  }

  function initialize() {
    enqueue(["initialize"], true)
  }

  function reapply() {
    if (!requestQueued("reapply")) enqueue(["reapply"], true)
  }

  function cycle() {
    enqueue(["cycle"], true)
  }

  function requestMode(mode) {
    if (mode !== "normal" && mode !== "safe" && mode !== "off") return
    enqueue(["mode", mode], true)
  }

  function requestSetting(key, value) {
    enqueue(["set", String(key), String(value)], true)
  }

  function requestReset() {
    enqueue(["reset"], true)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Component.onCompleted: initialize()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name === "configreloaded") reapplyTimer.restart()
      else if (name.indexOf("deviceadded") !== -1
               || name.indexOf("deviceremoved") !== -1) reapplyTimer.restart()
    }
  }

  Timer {
    id: reapplyTimer
    interval: 180
    onTriggered: root.reapply()
  }

  // Reconciliation is event-driven: the connections above already cover the
  // cases that can drift (a config reload, a device appearing or leaving).
  // This poll is read-only - `status` issues no `hyprctl eval` and writes no
  // state - so it keeps the icon and tooltip honest if something outside the
  // plugin changes the touchpad, without reasserting the profile on a loop.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "kdm.touchpad-guard"

    function cycle(): string { root.cycle(); return "queued" }
    function normal(): string { root.requestMode("normal"); return "queued" }
    function safe(): string { root.requestMode("safe"); return "queued" }
    function off(): string { root.requestMode("off"); return "queued" }
    function status(): string { return JSON.stringify(root.guardStatus) }
    function refresh(): string { root.refresh(); return "queued" }
    function set(key: string, value: string): string {
      root.requestSetting(key, value)
      return "queued"
    }
    function reset(): string { root.requestReset(); return "queued" }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  Process {
    id: controllerProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.controllerStdout = String(text || "").trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.controllerStderr = String(text || "").trim()
    }
    onExited: function(exitCode) {
      finishTimer.exitCode = exitCode
      finishTimer.restart()
    }
  }

  Timer {
    id: finishTimer
    interval: 0
    property int exitCode: 0
    onTriggered: root.finishRequest(exitCode)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.modeIcon(root.guardStatus.mode, root.guardStatus)
    active: root.guardStatus.mode === "safe"
    useActiveColor: true
    tooltipText: Model.modeTooltip(root.guardStatus)

    // No mouse button changes the mode. A clickpad reports only BTN_LEFT, so
    // libinput synthesises right-click from a two-finger press; a press it
    // reads as one finger arrives here as a left-click. When left-click
    // cycled, those misreads walked the mode into Typing Safe (which turns
    // off the tap gesture) and then Off (which turns off the touchpad),
    // removing the only way back into this panel. Cycling now lives on the
    // keyboard shortcut and on the panel's own mode row.
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
