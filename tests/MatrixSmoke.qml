import QtQuick
import Quickshell
import QtTest
import ".." as Plugin
FloatingWindow {
  id: window
  implicitWidth: 380; implicitHeight: 800; visible: true
  TestEvent { id: events }
  function keys() {
    var result = {}
    for (var layer = 0; layer < 2; layer++) for (var i = 0; i < 26; i++) {
      result[layer + ":" + i] = {layer: layer, index: i, value: i === 0 ? 0 : 4, name: i === 0 ? "NO" : "A", position: "#" + i}
    }
    return result
  }
  QtObject {
    id: service
    property var keymap: ({identity: "PRIVATE-ID", keys: window.keys(), codes: [], factory: window.keys(), info: {
      product: "Example & ISO #1", firmware_version: "1.2.3", serial: "PRIVATE-SERIAL",
      matrix: {rows: 2, cols: 12}, extra_entries: 2, layer_count: 2, layers_per_mode: 1,
      current_mode: {mode: 0}, modes: [{mode: 0, name: "mac"}, {mode: 1, name: "windows"}]}})
    property var drafts: ({})
    property var changes: []
    property var conflicts: ({})
    property bool keymapCurrent: true
    property bool actionBusy: false
    property bool detachedDraft: false
    property bool compatibleDraft: false
    property bool canApplyKeymap: false
    property bool ready: true
    function loadKeymap() {}
  }
  Plugin.KeymapEditor { id: editor; width: 360; height: 780; service: service }
  function child(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; ++i) { var found = child(item.children[i], name); if (found) return found }
    return null
  }
  Timer {
    interval: 300; running: true
    onTriggered: {
      try {
        var diagram = window.child(editor, "matrixDiagram")
        var scroll = window.child(editor, "matrixView")
        if (editor.air75 || !scroll.visible || !diagram.matrixMode) throw new Error("Missing generic view")
        if (diagram.width <= editor.width) throw new Error("Wide matrix squeezed below readable cell width")
        var key = window.child(diagram, "diagramKey-12")
        if (key.tooltipText.indexOf("Row 1, column 0 (#12)") < 0) throw new Error("Matrix coordinates incorrect")
        events.mouseClick(key, key.width/2, key.height/2, Qt.LeftButton, Qt.NoModifier, 1)
        if (editor.selected !== 12) throw new Error("Matrix click mapped to incorrect index")
        if (!window.child(diagram, "diagramKey-0").enabled) throw new Error("Zero assignment hidden or disabled")
        service.drafts = {"0:12": {value: 0x5225}}
        if (key.text !== "FN5") throw new Error("Matrix draft missing")
        editor.selectedLayer = 1
        if (key.text !== "A") throw new Error("Draft leaked across layers")
        scroll.contentItem.contentX = diagram.width - scroll.availableWidth
        var farKey = window.child(diagram, "diagramKey-23")
        events.mouseClick(farKey, farKey.width/2, farKey.height/2, Qt.LeftButton, Qt.NoModifier, 1)
        if (editor.selected !== 23) throw new Error("Scrolled matrix column not selectable")
        var extra = window.child(editor, "extraEntry-24")
        if (!extra || extra.entryIndex !== 24) throw new Error("Extra entry overlaps matrix")
        // Click the extra-control signal to test selection without depending on outer scroll position.
        extra.clicked()
        if (editor.selected !== 24) throw new Error("Extra entry selection incorrect")
        var url = editor.layoutIssueUrl()
        if (!url.startsWith("https://github.com/fldc/omarchy-nuphy/issues/new?template=keyboard-layout.md&title=Layout%20support%3A%20Example%20%26%20ISO%20%231&body=")) throw new Error("Issue URL not encoded")
        if (url.indexOf("PRIVATE") >= 0 || decodeURIComponent(url).indexOf("2 rows × 12 columns") < 0) throw new Error("Issue metadata incorrect")
        console.log("NuPhy matrix smoke passed")
        Qt.quit()
      } catch (error) { console.error(error); Qt.exit(1) }
    }
  }
}
