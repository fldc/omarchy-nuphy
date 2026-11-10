import QtQuick
import Quickshell.Io

Item {
  id: root
  property var shell: null
  property var workerCommand: ["python3", "-u", Qt.resolvedUrl("nuphy_worker.py").toString().replace(/^file:\/\//, "")]
  property var snapshot: ({})
  property var keymap: ({})
  property var settings: ({})
  property var settingsDraft: ({})
  property var settingsOriginal: ({})
  property string settingsDraftIdentity: ""
  readonly property bool settingsCurrent: !!settings.known && !!snapshot.connected && settings.identity === snapshot.deviceIdentity
  readonly property bool settingsDirty: Object.keys(settingsDraft).length > 0
  function discardSettings() { settingsDraft = ({}); settingsOriginal = ({}); settingsDraftIdentity = "" }
  function stageSetting(key, value) {
    if (!settingsCurrent || actionBusy) return
    var next = Object.assign({}, settingsDraft)
    var original = Object.assign({}, settingsOriginal)
    if (value === settings.values[key]) { delete next[key]; delete original[key] }
    else { if (!(key in original)) original[key] = settings.values[key]; next[key] = value }
    settingsDraftIdentity = settings.identity
    settingsDraft = next; settingsOriginal = original
  }
  function loadSettings(accessory, discard) {
    var accepted = request("settings-load", null, {accessory: accessory === true})
    if (accepted && discard) discardSettings()
    return accepted
  }
  function applySettings() {
    if (!settingsCurrent || !settingsDirty || settingsDraftIdentity !== settings.identity) return false
    return request("settings-apply", null, {identity: settings.identity, changes: settingsDraft, original: settingsOriginal})
  }
  function receiveSettings(value, completed) {
    settings = value
    if (completed && pendingAction === "settings-apply" && value.known && !value.error && value.message) discardSettings()
  }
  property var drafts: ({})
  property string pendingAction: ""
  readonly property bool keymapCurrent: !!keymap.known && !!snapshot.connected && keymap.identity === snapshot.deviceIdentity
  readonly property var changes: Object.keys(drafts).map(function(k) { return drafts[k] })

  property var draftOwner: ({})
  property var conflicts: ({})
  readonly property bool detachedDraft: changes.length > 0 && (draftOwner.identity !== keymap.identity || draftOwner.signature !== keymap.signature)
  readonly property bool compatibleDraft: !!draftOwner.signature && draftOwner.signature === keymap.signature
  readonly property bool canApplyKeymap: keymapCurrent && !detachedDraft && changes.length > 0 && Object.keys(conflicts).length === 0

  function reconcile() {
    if (!keymapCurrent || detachedDraft) return
    var next = Object.assign({}, drafts)
    var problems = {}
    Object.keys(next).forEach(function(k) {
      var current = keymap.keys[k]
      if (!current) { problems[k] = {missing: true}; return }
      if (current.value === next[k].value) delete next[k]
      else if (current.value !== next[k].original) problems[k] = {current: current.value}
    })
    drafts = next
    conflicts = problems
  }
  function stage(layer, index, value) {
    if (!keymapCurrent || actionBusy || detachedDraft) return
    var address = layer + ":" + index
    var current = keymap.keys[address]
    if (!current || !Number.isInteger(value) || value < 0 || value > 65535) return
    if (!changes.length) draftOwner = {identity: keymap.identity, stableIdentity: keymap.stableIdentity || "", signature: keymap.signature}
    var next = Object.assign({}, drafts)
    if (current.value === value) delete next[address]
    else next[address] = {layer: layer, index: index, original: next[address] ? next[address].original : current.value, value: value}
    drafts = next
    reconcile()
  }
  function resolve(address, keepEdit) {
    if (!keymapCurrent || actionBusy || detachedDraft || !conflicts[address]) return
    var next = Object.assign({}, drafts)
    if (keepEdit && keymap.keys[address]) next[address] = Object.assign({}, next[address], {original: keymap.keys[address].value})
    else delete next[address]
    drafts = next
    reconcile()
  }
  function bindDraft() {
    if (!keymapCurrent || actionBusy || !compatibleDraft) return
    draftOwner = {identity: keymap.identity, stableIdentity: keymap.stableIdentity || "", signature: keymap.signature}
    reconcile()
  }
  function discard() { drafts = ({}); conflicts = ({}); draftOwner = ({}) }
  function loadKeymap() { return request("keymap-load") }
  function applyKeymap() {
    if (!canApplyKeymap) return false
    return request("keymap-apply", null, {identity: keymap.identity, changes: changes})
  }
  function receiveKeymap(value) {
    keymap = value
    if (changes.length && value.known && draftOwner.identity !== value.identity &&
        draftOwner.stableIdentity && draftOwner.stableIdentity === value.stableIdentity && compatibleDraft) {
      draftOwner = Object.assign({}, draftOwner, {identity: value.identity})
    }
    reconcile()
  }
  onSnapshotChanged: {
    reconcile()
    if (settingsDraftIdentity && settingsDraftIdentity !== snapshot.deviceIdentity) discardSettings()
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
    if (action === "settings-load" || action === "settings-apply") settings = Object.assign({}, settings, {known: false, message: "", error: ""})
    process.write(JSON.stringify({id: pendingId, action: action, zone: zone, config: config}) + "\n")
    return true
  }

  function workerStopped() {
    actionBusy = false
    pendingId = -1
    snapshot = ({})
    keymap = Object.assign({}, keymap, {known: false})
    settings = Object.assign({}, settings, {known: false})
    if (!lastError) lastError = "NuPhy worker stopped; restarting"
    if (!restart.running) restart.start()
  }

  Process {
    id: process
    command: root.workerCommand
    stdinEnabled: true
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        try {
          const value = JSON.parse(line)
          if (value.zones) root.snapshot = value
          if (value.settings) root.receiveSettings(value.settings, value.requestId === root.pendingId && root.pendingId >= 0)
          if (value.keymap && value.requestId === root.pendingId) root.receiveKeymap(value.keymap)
          if (value.requestId === root.pendingId || value.protocolError) {
            root.actionBusy = false
            root.pendingId = -1
          }
          root.lastError = value.zones ? "" : String(value.error || "")
        } catch (error) { root.lastError = "Invalid NuPhy worker response" }
      }
    }
    stderr: SplitParser { onRead: function(line) { root.lastError = line.slice(0, 600) } }
    // FailedToStart changes running without emitting exited. Handle both paths.
    onRunningChanged: if (!running) root.workerStopped()
    onExited: root.workerStopped()
  }
  Timer { id: restart; interval: 5000; onTriggered: process.running = true }
}
