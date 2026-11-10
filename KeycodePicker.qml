pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Commons as Commons
import qs.Ui as Ui

ColumnLayout {
  id: root
  required property var codes
  required property int layerCount
  signal chosen(int value)
  signal closed()
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  readonly property var allCodes: codes.concat(Array.from({length: layerCount}, function(_, i) {
    return {name: "MO(" + i + ")", value: 0x5220 | i, group: "layer", description: "", aliases: ""}
  }))
  readonly property var filtered: allCodes.filter(function(k) {
    return (k.name + " " + k.group + " " + k.description + " " + k.aliases).toLowerCase().indexOf(search.text.toLowerCase()) >= 0
  })
  BoundedTextField {
    id: search; objectName: "keycodeSearch"
    Layout.fillWidth: true; placeholderText: strings.t("keymapSearch")
    foreground: Commons.Color.popups.text; maximumLength: 100
    Component.onCompleted: forceActiveFocus()
    Keys.onEscapePressed: root.closed()
  }
  Controls.ScrollView {
    Layout.fillWidth: true
    Layout.preferredHeight: Commons.Style.space(180)
    clip: true
    contentWidth: availableWidth
    ColumnLayout {
      width: parent.width
      Repeater {
        model: root.filtered
        delegate: Ui.Button {
          required property var modelData
          objectName: "keycode-" + modelData.value
          Layout.fillWidth: true
          text: modelData.name + " · " + modelData.group
          foreground: Commons.Color.popups.text; focusable: true
          onClicked: root.chosen(modelData.value)
        }
      }
    }
  }
  Ui.Button { text: strings.t("done"); focusable: true; onClicked: root.closed() }
}
