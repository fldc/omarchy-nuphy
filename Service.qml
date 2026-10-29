import QtQuick
import Quickshell.Io

Item {
  id: root
  property var shell: null
  property var snapshot: ({})
  property bool actionBusy: false
  property int nextId: 0
  property int pendingId: -1
  property string lastError: ""
  readonly property bool ready: process.running && !!snapshot.zones

  function request(action, zone, config) {
    if (!ready || actionBusy) return false
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
      if (!root.lastError) root.lastError = "NuPhy worker stopped; restarting"
      restart.restart()
    }
  }
  Timer { id: restart; interval: 5000; onTriggered: process.running = true }
}
