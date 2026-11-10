import QtQuick
import Quickshell
import ".." as Plugin

FloatingWindow {
  id: window
  implicitWidth: 100; implicitHeight: 100
  property bool failed: false
  property int ticks: 0
  Plugin.Service { id: service; workerCommand: ["/nonexistent/nuphy-worker-test"] }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      if (++window.ticks > 100) { console.error("Failed worker did not recover: " + service.lastError); Qt.exit(1) }
      if (!window.failed && service.lastError.length) {
        if (service.ready || service.actionBusy || service.keymap.known) { Qt.exit(1); return }
        window.failed = true
        service.workerCommand = ["python3", "-u", Quickshell.env("NUPHY_TEST_WORKER")]
      } else if (window.failed && service.ready) {
        console.log("NuPhy recovery smoke passed")
        Qt.quit()
      }
    }
  }
}
