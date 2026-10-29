import QtQuick
import Quickshell
import ".." as Plugin

FloatingWindow {
  id: window
  implicitWidth: 420
  implicitHeight: 800
  visible: true
  property int appliedCount: 0
  property string appliedZone: ""
  Plugin.LightingEditor {
    id: editor
    width: 360
    height: 700
    ready: true
    snapshot: ({keyboardName: "NuPhy Test", theme: "#123456", zones: {
      main: {effect: "static", hex: "#123456", brightness: 70, speed: 2, direction: "right", sync: false, offset: 17},
      side: {effect: "neon", hex: "#abcdef", brightness: 40, speed: 1, direction: "right", sync: false, offset: 17},
      decorative: {effect: "static", hex: "#ffffff", brightness: 30, speed: 3, direction: "right", sync: false, offset: 35}
    }})
    onApplyRequested: function(zone, config) { window.appliedCount++; window.appliedZone = zone }
  }

  function child(item, name) {
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var result = child(children[i], name)
      if (result) return result
    }
    return null
  }
  function check(value, message) {
    if (!value) throw new Error(message)
  }
  Timer {
    interval: 300
    running: true
    onTriggered: {
      try {
        var brightness = window.child(editor, "brightness")
        window.check(brightness !== null, "brightness slider exists")
        window.check(brightness.value === 70, "initial preferences loaded")
        brightness.value = 55
        editor.selectZone("side")
        window.check(brightness.value === 40, "zone preferences change")
        editor.apply()
        window.check(window.appliedCount === 1 && window.appliedZone === "side", "apply targets selected zone")
        editor.selectZone("main")
        window.check(brightness.value === 55, "draft survives zone switch")
        var button = window.child(editor, "applyButton")
        var idleText = button.text
        editor.snapshot = Object.assign({}, editor.snapshot, {theme: "#654321"})
        window.check(button.text === idleText && button.enabled, "background updates do not flicker button")
        editor.actionBusy = true
        window.check(!button.enabled && button.text !== idleText, "action busy state")
        editor.actionBusy = false
        var input = window.child(editor, "hexInput")
        input.text = "#nope"
        editor.apply()
        window.check(window.appliedCount === 1 && editor.localError.length > 0, "invalid colors do not apply")
        editor.syncing = true
        editor.apply()
        window.check(window.appliedCount === 2 && editor.config().hex === "#123456", "theme sync ignores incomplete manual color")
        var scroll = window.child(editor, "verticalScroll")
        window.check(scroll !== null && scroll.x > editor.width / 2, "scrollbar placed away from title")
        console.log("NuPhy UI smoke passed")
        Qt.quit()
      } catch (error) {
        console.error("NuPhy UI smoke FAILED: " + error)
        Qt.exit(1)
      }
    }
  }
}
