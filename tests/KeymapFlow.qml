import QtQuick
import Quickshell
import QtTest
import ".." as Plugin
FloatingWindow {
  id: window
  implicitWidth: 800; implicitHeight: 800; visible: true
  property int phase: 0
  property int ticks: 0
  TestEvent { id: events }
  Plugin.Service { id: service; workerCommand: ["python3", "-u", Quickshell.env("NUPHY_TEST_WORKER")] }
  Plugin.KeymapEditor { id: editor; width: 760; height: 660; service: service }
  Plugin.KeymapEditor { id: second; visible: false; service: service }
  function child(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; ++i) { var found = child(item.children[i], name); if (found) return found }
    return null
  }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      try {
        if (++window.ticks > 80) throw new Error("Flow timed out: " + service.lastError)
        if (service.actionBusy) return
        if (window.phase === 0 && service.ready) { service.loadKeymap(); window.phase = 1 }
        else if (window.phase === 1 && service.keymapCurrent) {
          var matrix = window.child(editor, "matrixDiagram")
          var matrixKey = window.child(matrix, "diagramKey-0")
          events.mouseClick(matrixKey, matrixKey.width/2, matrixKey.height/2, Qt.LeftButton, Qt.NoModifier, 1)
          if (editor.selected !== 0) throw new Error("Matrix selection failed")
          var choose = window.child(editor, "keymapChoose")
          events.mouseClick(choose, choose.width/2, choose.height/2, Qt.LeftButton, Qt.NoModifier, 1)
          var search = window.child(editor, "keycodeSearch")
          search.text = "B"
          var code = window.child(editor, "keycode-5")
          events.mouseClick(code, code.width/2, code.height/2, Qt.LeftButton, Qt.NoModifier, 1)
          second.selected = 0
          if (second.draft.value !== 5) throw new Error("Shared draft missing")
          var apply = window.child(editor, "keymapApply")
          events.mouseClick(apply, apply.width/2, apply.height/2, Qt.LeftButton, Qt.NoModifier, 1)
          window.phase = 2
        } else if (window.phase === 2) {
          if (service.keymap.error || service.changes.length || service.keymap.keys["0:0"].value !== 5) throw new Error("Apply failed: " + service.keymap.error)
          console.log("NuPhy keymap flow passed")
          Qt.quit()
        }
      } catch (error) { console.error(error); Qt.exit(1) }
    }
  }
}
