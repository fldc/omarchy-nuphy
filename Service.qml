import QtQuick
import Quickshell.Io

Item {
  id: root
  property var shell: null
  property var snapshot: ({})
  property var keymap: ({})
  property var drafts: ({})
  property string pendingAction: ""
  readonly property bool keymapCurrent: !!keymap.known && !!snapshot.connected && keymap.identity === snapshot.deviceIdentity
  readonly property var changes: Object.keys(drafts).map(function(k) { return drafts[k] })

  function stage(layer, index, value) {
    if (!keymapCurrent || actionBusy) return
    var address = layer + ":" + index
    var current = keymap.keys[address]
    if (!current || !Number.isInteger(value) || value < 0 || value > 65535) return
    var next = Object.assign({}, drafts)
    if (current.value === value) delete next[address]
    else next[address] = {layer: layer, index: index, original: current.value, value: value}
    drafts = next
  }
  function discard() { drafts = ({}) }
  function loadKeymap() { return request("keymap-load") }
  function applyKeymap() {
    if (!keymapCurrent || !changes.length) return false
    return request("keymap-apply", null, {identity: keymap.identity, changes: changes})
  }
  function receiveKeymap(value) {
    if (keymap.identity && value.identity && keymap.identity !== value.identity) drafts = ({})
    keymap = value
    if (value.known) {
      var next = Object.assign({}, drafts)
      Object.keys(next).forEach(function(k) {
        if (value.keys[k] && value.keys[k].value === next[k].value) delete next[k]
      })
      drafts = next
    }
  }
  property bool actionBusy: false
  property int nextId: 0
  property int pendingId: -1
  property string lastError: ""
  readonly property bool ready: process.running && !!snapshot.zones

  function request(action, zone, config) {
    if (!ready || actionBusy) return false
    pendingAction = action
    pendingId = ++nextId
    actionBusy = true
    lastError = ""
    process.write(JSON.stringify({id: pendingId, action: action, zone: zone, config: config}) + "\n")
    return true
  }

  Process {
    id: process
    command: ["python3", "-u", Qt.resolvedUrl("nuphy_worker.py").toString().replace(/^file:\/\//, "")]
    stdinEnabled: true
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          const value = JSON.parse(line)
          if (value.zones) root.snapshot = value
          if (value.keymap) root.receiveKeymap(value.keymap)
          if (value.requestId === root.pendingId || value.protocolError) {
            root.actionBusy = false
            root.pendingId = -1
          }
          root.lastError = value.zones ? "" : String(value.error || "")
        } catch (error) { root.lastError = "Invalid NuPhy worker response" }
      }
    }
    stderr: SplitParser { onRead: function(line) { root.lastError = line.slice(0, 600) } }
    onExited: {
      root.actionBusy = false
      root.pendingId = -1
      root.snapshot = ({})
      root.keymap = Object.assign({}, root.keymap, {known: false})
      if (!root.lastError) root.lastError = "NuPhy worker stopped; restarting"
      restart.restart()
    }
  }
  Timer { id: restart; interval: 5000; onTriggered: process.running = true }
}
