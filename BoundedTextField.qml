import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Io
import qs.Ui as Ui

// Keep normal typing/IME editing, but never use Qt's synchronous clipboard reader.
Ui.TextField {
  id: root
  property string pasteError: ""
  property string pasteSelection: "clipboard"
  property string pasteOriginal: ""
  property int pasteStart: 0
  property int pasteEnd: 0
  property var pasteCommand: ["python3", Qt.resolvedUrl("nuphy_io.py").toString().replace(/^file:\/\//, ""), "paste", pasteSelection]
  readonly property bool pasteBusy: clipboard.running

  function requestPaste(primary) {
    if (!enabled || readOnly || pasteBusy) return
    forceActiveFocus()
    pasteError = ""
    pasteSelection = primary ? "primary" : "clipboard"
    pasteOriginal = text
    pasteStart = selectionStart
    pasteEnd = selectionEnd
    clipboard.running = true
  }
  function receivePaste(line) {
    try {
      var value = JSON.parse(line)
      // Do not insert a delayed reply after typing, moving the cursor or switching fields.
      if (!enabled || readOnly || !activeFocus || text !== pasteOriginal ||
          selectionStart !== pasteStart || selectionEnd !== pasteEnd) return
      if (typeof value.text !== "string") throw new Error("Invalid clipboard response")
      var incoming = value.text.replace(/[\r\n]/g, " ").slice(0, maximumLength - (text.length - (pasteEnd - pasteStart)))
      remove(pasteStart, pasteEnd)
      insert(pasteStart, incoming)
      cursorPosition = pasteStart + incoming.length
    } catch (error) { pasteError = "Unable to paste clipboard text" }
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (event.matches(StandardKey.Paste)) {
      event.accepted = true
      requestPaste(false)
    }
  }
  // Catch the entire middle-button gesture before TextInput can request PRIMARY.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton | Qt.RightButton
    onPressed: function(mouse) {
      root.forceActiveFocus()
      if (mouse.button === Qt.MiddleButton) {
        root.cursorPosition = root.positionAt(mouse.x, mouse.y)
        root.requestPaste(true)
      } else menu.popup()
    }
  }
  Controls.ContextMenu.menu: menu
  // An explicit menu also prevents style-provided native paste actions.
  Controls.Menu {
    id: menu
    Controls.MenuItem { text: qsTr("Cut"); enabled: root.selectedText.length > 0; onTriggered: root.cut() }
    Controls.MenuItem { text: qsTr("Copy"); enabled: root.selectedText.length > 0; onTriggered: root.copy() }
    Controls.MenuItem { text: qsTr("Paste"); enabled: !root.readOnly && !root.pasteBusy; onTriggered: root.requestPaste(false) }
    Controls.MenuItem { text: qsTr("Select all"); onTriggered: root.selectAll() }
  }
  Process {
    id: clipboard
    command: root.pasteCommand
    stdout: SplitParser { onRead: function(line) { root.receivePaste(line) } }
    stderr: SplitParser { onRead: function(line) { root.pasteError = line.slice(0, 600) } }
    onExited: function(code) { if (code !== 0 && !root.pasteError) root.pasteError = "Clipboard unavailable" }
  }
  Controls.ToolTip.visible: hovered && pasteError.length > 0
  Controls.ToolTip.text: pasteError
}
