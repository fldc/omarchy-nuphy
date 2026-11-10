import QtQuick
import Quickshell
import QtTest
import ".." as Plugin

FloatingWindow {
  id: window
  implicitWidth: 420; implicitHeight: 800; visible: true
  property int phase: 0
  property int ticks: 0
  TestEvent { id: events }
  Plugin.Service { id: service; workerCommand: ["python3", "-u", Quickshell.env("NUPHY_TEST_WORKER")] }
  Plugin.NuphyEditor { id: editor; width: 380; height: 760; service: service }
  Plugin.SettingsEditor { id: second; visible: false; service: service }
  function child(item, name) {
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; ++i) { var found = child(item.children[i], name); if (found) return found }
    return null
  }
  function check(value, message) { if (!value) throw new Error(message) }
  Timer {
    interval: 100; running: true; repeat: true
    onTriggered: {
      try {
        if (++window.ticks > 100) throw new Error("Settings flow timed out: " + service.lastError)
        if (service.actionBusy) return
        if (window.phase === 0 && service.ready) {
          window.child(editor, "settingsTab").clicked()
          window.phase = 1
        } else if (window.phase === 1 && service.settingsCurrent) {
          window.check(editor.settingsTab && !editor.keymapTab, "Settings tab selects new editor")
          window.check(!second.accessoryKnown, "Accessory must not be probed automatically")
          window.child(editor, "autoSleep").clicked()
          window.check(service.settingsDraft.auto_sleep === false && second.value("auto_sleep") === false, "Shared draft stages toggle")
          window.check(service.settings.values.auto_sleep === true, "Staging never updates keyboard state")
          window.check(!window.child(editor, "level1_minutes-plus").enabled, "Disabled sleep preserves inactive timer")
          window.child(editor, "settingsApply").clicked()
          window.check(!service.settingsCurrent && service.actionBusy, "Apply requires fresh readback before further edits")
          window.phase = 2
        } else if (window.phase === 2) {
          window.check(service.settingsCurrent && !service.settings.error && !service.settingsDirty, "Verified Apply clears drafts")
          window.check(service.settings.values.auto_sleep === false && service.settings.values.level1_minutes === 6 && service.settings.values.level2_minutes === 24, "Disabling sleep preserves timers")
          window.child(editor, "autoSleep").clicked()
          service.receiveSettings(service.settings, false)
          window.check(service.settingsDirty, "Background snapshots cannot clear a new draft")
          service.stageSetting("level1_minutes", 127)
          window.check(!window.child(editor, "level1_minutes-plus").enabled, "Upper timer limit")
          service.stageSetting("level1_minutes", 5)
          window.check(!window.child(editor, "level1_minutes-minus").enabled, "Lower timer limit")
          window.child(editor, "settingsDiscard").clicked()
          window.check(!service.settingsDirty && second.value("level1_minutes") === 6, "Discard restores shared readings")
          window.child(editor, "readAccessory").clicked()
          window.phase = 3
        } else if (window.phase === 3 && service.settingsCurrent) {
          window.check(second.accessoryKnown && second.value("accessory") === "knob", "Explicit accessory read")
          window.child(editor, "accessorySwitch").changed("button")
          window.child(editor, "settingsApply").clicked()
          window.phase = 4
        } else if (window.phase === 4) {
          window.check(!service.settings.error && service.settings.values.accessory === "button" && !service.settingsDirty, "Accessory verified")
          service.stageSetting("auto_sleep", true)
          service.snapshot = Object.assign({}, service.snapshot, {connected: false, deviceIdentity: ""})
          window.check(!service.settingsCurrent && !service.settingsDirty && !window.child(editor, "settingsApply").enabled, "Disconnect blocks stale drafts")
          console.log("NuPhy settings flow passed")
          Qt.quit()
        }
      } catch (error) { console.error(error); Qt.exit(1) }
    }
  }
}
