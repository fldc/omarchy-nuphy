import QtQuick
import Quickshell
import QtTest
import ".." as Plugin

FloatingWindow {
  id: window
  implicitWidth: 420
  implicitHeight: 800
  visible: true
  property int appliedCount: 0
  property string appliedZone: ""
  TestEvent { id: events }
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
        events.mouseWheel(brightness, brightness.width / 2, brightness.height / 2, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
        window.check(brightness.value === 70, "delivered wheel event cannot change brightness")
        events.mouseClick(brightness, brightness.width * 0.25, brightness.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
        window.check(brightness.value < 50, "wheel shield still permits slider clicks")
        brightness.value = 70
        editor.height = 300
        var wheel = {pixelDelta: Qt.point(0, 0), angleDelta: Qt.point(0, -120), accepted: false}
        brightness.handleWheel(wheel)
        window.check(wheel.accepted && editor.contentItem.contentY > 0, "wheel is consumed and scrolls popup")
        var speed = window.child(editor, "speed")
        var oldSpeed = speed.value
        editor.height = 700
        editor.contentItem.contentY = 0
        events.mouseWheel(speed, speed.width / 2, speed.height / 2, Qt.NoButton, Qt.NoModifier, 0, 120, 1)
        window.check(speed.value === oldSpeed, "delivered wheel event cannot change speed")
        speed.handleWheel({pixelDelta: Qt.point(0, -10), angleDelta: Qt.point(0, 0), accepted: false})
        window.check(speed.value === oldSpeed, "touchpad cannot change speed")
        editor.contentItem.contentY = 0
        brightness.value = 55
        editor.selectZone("side")
        window.check(brightness.value === 40, "zone preferences change")
        editor.apply()
        window.check(window.appliedCount === 1 && window.appliedZone === "side", "apply targets selected zone")
        editor.selectZone("main")
        window.check(brightness.value === 55, "draft survives zone switch")
        var button = window.child(editor, "applyButton")
        editor.snapshot = Object.assign({}, editor.snapshot, {setupIssue: "cli-missing"})
        window.check(!button.enabled && window.child(editor, "setupNotice").visible, "missing CLI shows manual setup and blocks Apply")
        editor.snapshot = Object.assign({}, editor.snapshot, {setupIssue: "hid-permission"})
        window.check(!button.enabled && window.child(editor, "setupNotice").text.indexOf("HID") >= 0, "missing HID permission shows setup instructions")
        editor.snapshot = Object.assign({}, editor.snapshot, {setupIssue: ""})
        window.check(button.enabled, "Apply enabled after setup recovery")
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
        var pickerLoader = window.child(editor, "colorPickerLoader")
        window.check(pickerLoader !== null && pickerLoader.item === null, "picker is lazy")
        editor.toggleColorPicker()
        var picker = pickerLoader.item
        window.check(picker !== null, "clicking square opens picker")
        var hueSlider = window.child(picker, "hueSlider")
        var oldHue = picker.hue
        hueSlider.handleWheel({pixelDelta: Qt.point(0, 0), angleDelta: Qt.point(0, 120), accepted: false})
        window.check(picker.hue === oldHue, "wheel cannot change hue")
        window.check(picker.selectedColor.toString() === "#654321", "picker opens at current theme color")
        window.check(window.appliedCount === 2, "opening picker does not apply lighting")
        picker.setColor("#ff0000")
        picker.selectHue(1 / 3)
        window.check(input.text === "#00ff00" && !editor.syncing, "hue selection updates hex and selects manual mode")
        window.check(window.appliedCount === 2, "color preview does not send commands")
        picker.select(0, 1)
        window.check(input.text === "#ffffff", "saturation/value selection supports white")
        picker.select(1, 0)
        window.check(input.text === "#000000", "saturation/value selection supports black")
        input.text = "#112233"
        window.check(picker.selectedColor.toString() === "#112233", "hex edits update picker")
        editor.syncing = true
        window.check(!editor.pickerOpen, "enabling theme sync closes picker")
        editor.toggleColorPicker()
        picker = pickerLoader.item
        picker.closed()
        window.check(!editor.pickerOpen, "Done closes picker")
        editor.toggleColorPicker()
        editor.selectZone("side")
        window.check(!editor.pickerOpen, "switching zones closes picker")
        editor.selectZone("decorative")
        window.check(editor.zone === "side" && editor.activeZones.indexOf("decorative") < 0, "decorative zone is unavailable")
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
