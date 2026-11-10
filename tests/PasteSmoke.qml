import QtQuick
import Quickshell
import QtTest
import ".." as Plugin

FloatingWindow {
  id: window
  implicitWidth: 420; implicitHeight: 200; visible: true
  property int phase: 0
  property int ticks: 0
  TestEvent { id: events }
  Plugin.BoundedTextField { id: field; width: 300; maximumLength: 7; selectByMouse: true }
  Timer {
    interval: 50; running: true; repeat: true
    onTriggered: {
      try {
        if (++window.ticks > 100) throw new Error("Paste test timed out: " + field.pasteError)
        if (field.pasteBusy) return
        if (window.phase === 0) {
          field.forceActiveFocus()
          events.keyClick(Qt.Key_A, Qt.NoModifier, 1)
          if (field.text !== "a") throw new Error("Normal typing failed")
          field.selectAll()
          events.keyClick(Qt.Key_V, Qt.ControlModifier, 1)
          window.phase = 1
        } else if (window.phase === 1) {
          if (field.text !== "#abc") throw new Error("Ctrl+V did not use bounded helper: " + field.text)
          field.selectAll()
          events.keyClick(Qt.Key_Insert, Qt.ShiftModifier, 1)
          window.phase = 2
        } else if (window.phase === 2) {
          if (field.text !== "#abc") throw new Error("Shift+Insert failed")
          field.text = ""
          events.mouseClick(field, 5, field.height / 2, Qt.MiddleButton, Qt.NoModifier, 1)
          window.phase = 3
        } else if (window.phase === 3) {
          if (field.text !== "#abc" || field.pasteSelection !== "primary") throw new Error("PRIMARY paste failed")
          field.cursorPosition = field.text.length
          field.requestPaste(false)
          window.phase = 4
        } else if (window.phase === 4) {
          if (field.text !== "#abc#ab") throw new Error("Field size bound failed: " + field.text)
          field.selectAll()
          field.requestPaste(false)
          field.text = "new"
          window.phase = 5
        } else {
          if (field.text !== "new") throw new Error("Delayed paste replaced new edit")
          console.log("NuPhy paste smoke passed")
          Qt.quit()
        }
      } catch (error) { console.error(error); Qt.exit(1) }
    }
  }
}
