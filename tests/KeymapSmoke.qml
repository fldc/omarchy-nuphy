import QtQuick
import Quickshell
import QtTest
import ".." as Plugin
FloatingWindow {
  id: window
  implicitWidth: 800; implicitHeight: 800; visible: true
  QtObject {
    id: service
    property var snapshot: ({})
    property bool ready: true
    property bool actionBusy: false
    property string lastError: ""
    property bool keymapCurrent: true
    property bool detachedDraft: false
    property bool compatibleDraft: false
    property bool canApplyKeymap: false
    property var conflicts: ({})
    property var drafts: ({})
    property var changes: Object.keys(drafts).map(function(k) { return drafts[k] })
    property var keymap: ({identity: "test", known: true, keys: {"0:0": {layer: 0, index: 0, position: "ESC", name: "ESC", value: 41}}, factory: {"0:0": {name: "ESC", value: 41}}, codes: [{name: "A", value: 4, group: "basic", aliases: "", description: ""}], info: {product: "NuPhy Air75 V3", matrix: {rows: 6, cols: 16}, extra_entries: 2, layer_count: 8, layers_per_mode: 4, modes: [{mode: 0, name: "mac"}, {mode: 1, name: "windows"}], current_mode: {mode: 0}}})
    function stage(layer, index, value) { drafts = {"0:0": {layer: layer, index: index, value: value, original: 41}} }
    function loadKeymap() {}
    function applyKeymap() {}
    function discard() { drafts = ({}) }
  }
  TestEvent { id: events }
  property int selectedIndex: -1
  Plugin.KeyboardLayout {
    id: diagram; width: 640; z: 10
    keys: ({"0:14": {position: "YELLOW", name: "DEL", value: 76}, "0:91": {position: "FN", name: "MO(5)", value: 0x5225}})
    drafts: ({})
    selectedLayer: 0
    onSelectedKey: function(index) { window.selectedIndex = index }
  }
  function child(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; ++i) { var found = child(item.children[i], name); if (found) return found }
    return null
  }
  Plugin.Service { id: realService }
  Plugin.NuphyEditor { id: editor; width: 760; height: 740; service: service; keymapTab: true }
  Plugin.KeymapEditor { id: keymap; width: 760; height: 660; visible: false; service: service }
  Timer {
    interval: 300; running: true
    onTriggered: {
      try {
        var seen = {}
        diagram.rows.forEach(function(row) {
          var end = 0
          row.forEach(function(position) {
            if (seen[position[0]] || position[1] !== end) throw new Error("Duplicate key or physical gap")
            seen[position[0]] = true
            end = position[1] + position[2]
          })
          if (end !== 16) throw new Error("Physical row not 16 units")
        })
        var del = window.child(diagram, "diagramKey-14")
        var fn = window.child(diagram, "diagramKey-91")
        if (del.text !== "DEL" || fn.text !== "FN5") throw new Error("Assignments differ from physical legends")
        diagram.drafts = {"0:14": {value: 0x5226}}
        if (del.text !== "FN6") throw new Error("Pending assignment not previewed")
        events.mouseClick(del, del.width/2, del.height/2, Qt.LeftButton, Qt.NoModifier, 1)
        if (window.selectedIndex !== 14) throw new Error("Physical key selected wrong matrix index")
        if (!keymap.air75) throw new Error("Air75 layout not recognized")
        keymap.selected = 0
        keymap.stage(4)
        if (service.changes.length !== 1 || service.changes[0].value !== 4) throw new Error("Draft not staged")
        keymap.pickerOpen = true
        service.keymapCurrent = false
        keymap.stage(5)
        if (service.changes[0].value !== 4) throw new Error("Stale edit accepted")
        realService.snapshot = {zones: {}, connected: true, deviceIdentity: "test"}
        realService.receiveKeymap(service.keymap)
        realService.stage(0, 0, 4)
        if (realService.changes.length !== 1) throw new Error("Shared draft missing")
        realService.receiveKeymap(service.keymap)
        if (realService.changes.length !== 1) throw new Error("Refresh discarded draft")
        realService.snapshot = {zones: {}, connected: false}
        realService.stage(0, 0, 5)
        if (realService.changes[0].value !== 4) throw new Error("Disconnected edit accepted")
        realService.receiveKeymap(Object.assign({}, service.keymap, {identity: "other"}))
        if (realService.changes.length !== 1 || !realService.detachedDraft) throw new Error("Detached draft lost")
        realService.discard()
        realService.snapshot = {zones: {}, connected: true, deviceIdentity: "test"}
        realService.receiveKeymap(Object.assign({}, service.keymap, {signature: "layout", stableIdentity: "serial1"}))
        realService.stage(0, 0, 4)
        var modified = Object.assign({}, realService.keymap, {keys: {"0:0": {layer: 0, index: 0, value: 5}}})
        realService.receiveKeymap(modified)
        if (!realService.conflicts["0:0"] || realService.canApplyKeymap) throw new Error("Conflict not blocked")
        realService.resolve("0:0", true)
        if (realService.changes[0].original !== 5 || !realService.canApplyKeymap) throw new Error("Conflict acknowledgement failed")
        realService.snapshot = {zones: {}, connected: true, deviceIdentity: "reconnected"}
        realService.receiveKeymap(Object.assign({}, modified, {identity: "reconnected"}))
        if (realService.detachedDraft || realService.changes.length !== 1) throw new Error("Identified reconnect lost draft")
        realService.snapshot = {zones: {}, connected: true, deviceIdentity: "unknown"}
        realService.receiveKeymap(Object.assign({}, modified, {identity: "unknown", stableIdentity: ""}))
        if (!realService.detachedDraft) throw new Error("Unknown keyboard auto-attached")
        realService.bindDraft()
        if (realService.detachedDraft) throw new Error("Explicit draft binding failed")
        editor.width = 360
        console.log("NuPhy keymap smoke passed")
        Qt.quit()
      } catch (error) { console.error(error); Qt.exit(1) }
    }
  }
}
